#ifndef MEMORY_H
#define MEMORY_H

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <psapi.h>

#elif defined(__unix__) || defined(__unix) || defined(unix) || (defined(__APPLE__) && defined(__MACH__))
#include <unistd.h>
#include <sys/resource.h>

#if defined(__APPLE__) && defined(__MACH__)
#include <mach/mach.h>

#elif (defined(_AIX) || defined(__TOS__AIX__)) || (defined(__sun__) || defined(__sun) || defined(sun) && (defined(__SVR4) || defined(__svr4__)))
#include <fcntl.h>
#include <procfs.h>

#elif defined(__linux__) || defined(__linux) || defined(linux) || defined(__gnu_linux__)
#include <stdio.h>

#endif

#else
#error "Cannot define getCurrentRSS( ) for an unknown OS."
#endif

size_t getPeakRSS();
size_t getCurrentRSS();

#if defined(__cplusplus)
}
#endif

#endif