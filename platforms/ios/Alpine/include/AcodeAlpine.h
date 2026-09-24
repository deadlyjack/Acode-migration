#pragma once
#include <stdbool.h>
#include <stddef.h>

typedef void (*AlpineExitCallback)(int pid, int status);

// Calls that access guest state are serialized by AlpineRuntime.queue.
int alpine_boot(const char *root, AlpineExitCallback callback);
int alpine_bind(const char *guest, const char *host, bool readOnly);
int alpine_chmod(const char *path, unsigned int mode);
int alpine_start(const char *command, const char *environment, int input, int output, int error);
int alpine_kill(int pid);
bool alpine_running(int pid);
void alpine_reap(void);
void alpine_stop_all(void);
bool alpine_idle(void);
int alpine_unmount(void);
bool alpine_import(const char *archive, const char *root, char *error, size_t capacity);
void alpine_install_fault_handlers(void);
