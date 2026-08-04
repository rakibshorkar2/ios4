#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <io.h>
#define EXPORT __declspec(dllexport)
#else
#include <unistd.h>
#include <fcntl.h>
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C" {

// Writes a chunk of bytes to a specific offset in a file.
// Returns 1 on success, 0 on failure.
EXPORT int WriteChunk(const char* filePath, const uint8_t* data, int length, int64_t offset) {
    if (filePath == nullptr || data == nullptr || length <= 0) {
        return 0; // Invalid arguments
    }

#if defined(_WIN32)
    FILE* file = fopen(filePath, "r+b");
    if (file == nullptr) {
        file = fopen(filePath, "wb");
        if (file == nullptr) return 0;
    }
    if (_fseeki64(file, offset, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
#else
    FILE* file = fopen(filePath, "r+b");
    if (file == nullptr) {
        file = fopen(filePath, "wb"); // Create if missing
        if (file == nullptr) return 0;
    }
    if (fseeko(file, offset, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
#endif

    size_t written = fwrite(data, 1, length, file);
    fclose(file);

    return (written == length) ? 1 : 0;
}

// Hashing functions (stub/placeholder for actual high-performance C++ implementation)
// In a real scenario, we'd use OpenSSL or a fast header-only lib like 'hash-library'
EXPORT int GetFileHash(const char* filePath, char* hashResult, int algorithm) {
    if (filePath == nullptr || hashResult == nullptr) return 0;

    FILE* file = fopen(filePath, "rb");
    if (file == nullptr) return 0;

    // This is a simplified placeholder. 
    // For "Next Level", we would use one-pass streaming hash to avoid memory spikes.
    // For now, we return a success signal for the architecture setup.
    // Actual implementation would involve buffer-based hashing.
    
    fclose(file);
    strcpy(hashResult, "HASH_STUB_IMPLEMENTED_IN_NATIVE_IO");
    return 1;
}

// Pre-allocates disk space for a file to prevent fragmentation and mid-download failures.
EXPORT int PreAllocateDisk(const char* filePath, int64_t size) {
    if (filePath == nullptr || size <= 0) return 0;

    FILE* file = fopen(filePath, "ab"); // Open or create
    if (file == nullptr) return 0;

#if defined(_WIN32)
    // On Windows, we'd use SetFilePointerEx and SetEndOfFile or _chsize_s
    int fd = _fileno(file);
    if (_chsize_s(fd, size) != 0) {
        fclose(file);
        return 0;
    }
#else
    // On Linux/Android, posix_fallocate is ideal
    int fd = fileno(file);
    if (posix_fallocate(fd, 0, size) != 0) {
        // Fallback for filesystems that don't support fallocate
        if (ftruncate(fd, size) != 0) {
            fclose(file);
            return 0;
        }
    }
#endif

    fclose(file);
    return 1;
}

}
