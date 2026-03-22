#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

int pty_spawn(int *master_fd, int *child_pid_out, uint16_t cols, uint16_t rows) {
    struct winsize ws = {
        .ws_col = cols,
        .ws_row = rows,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    int master;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) {
        return -1;
    }

    if (pid == 0) {
        // Child process
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        unsetenv("GHOSTTY_RESOURCES_DIR");

        const char *shell = getenv("SHELL");
        if (!shell) shell = "/bin/zsh";

        const char *shell_name = strrchr(shell, '/');
        shell_name = shell_name ? shell_name + 1 : shell;

        // Login shell (prefix with -)
        char login_name[256];
        snprintf(login_name, sizeof(login_name), "-%s", shell_name);

        execl(shell, login_name, NULL);
        _exit(127);
    }

    // Parent process — set non-blocking
    int flags = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);

    *master_fd = master;
    *child_pid_out = pid;
    return 0;
}

ssize_t pty_read(int fd, uint8_t *buf, size_t len) {
    return read(fd, buf, len);
}

ssize_t pty_write(int fd, const uint8_t *buf, size_t len) {
    return write(fd, buf, len);
}

int pty_resize(int fd, uint16_t cols, uint16_t rows) {
    struct winsize ws = {
        .ws_col = cols,
        .ws_row = rows,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    return ioctl(fd, TIOCSWINSZ, &ws);
}

void pty_close(int fd, int child_pid) {
    close(fd);
    if (child_pid > 0) {
        kill(child_pid, SIGHUP);
        waitpid(child_pid, NULL, 0);
    }
}
