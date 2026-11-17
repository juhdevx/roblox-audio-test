#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace voiceshift::dsp {

// Bounded, lock-free single-producer / single-consumer ring buffer.
//
// * Exactly one thread may call the producer methods (write, availableToWrite, framesWritten).
// * Exactly one thread may call the consumer methods (read, peek, skip, availableToRead, framesRead).
// * Indices grow monotonically and wrap naturally; capacity is a power of two.
// * framesWritten()/framesRead() are 64-bit stream positions that serve as sample timestamps.
// Construction allocates; nothing else does.
template <typename T>
class SpscRingBuffer {
public:
    explicit SpscRingBuffer(size_t minCapacity)
        : capacity_(nextPowerOfTwo(std::max<size_t>(minCapacity, 2))),
          mask_(capacity_ - 1),
          buffer_(capacity_) {}

    size_t capacity() const { return capacity_; }

    size_t availableToRead() const {
        const size_t w = write_.load(std::memory_order_acquire);
        const size_t r = read_.load(std::memory_order_acquire);
        return w - r;
    }

    size_t availableToWrite() const { return capacity_ - availableToRead(); }

    // Producer. Returns the number of elements written (may be < count when full).
    size_t write(const T* data, size_t count) {
        const size_t w = write_.load(std::memory_order_relaxed);
        const size_t r = read_.load(std::memory_order_acquire);
        const size_t space = capacity_ - (w - r);
        const size_t n = std::min(count, space);
        const size_t start = w & mask_;
        const size_t first = std::min(n, capacity_ - start);
        std::copy(data, data + first, buffer_.begin() + static_cast<std::ptrdiff_t>(start));
        std::copy(data + first, data + n, buffer_.begin());
        write_.store(w + n, std::memory_order_release);
        totalWritten_ += n;
        return n;
    }

    // Consumer. Returns the number of elements read.
    size_t read(T* out, size_t count) {
        const size_t n = peek(out, count);
        skip(n);
        return n;
    }

    // Consumer. Copies without consuming.
    size_t peek(T* out, size_t count) const {
        const size_t r = read_.load(std::memory_order_relaxed);
        const size_t w = write_.load(std::memory_order_acquire);
        const size_t n = std::min(count, w - r);
        const size_t start = r & mask_;
        const size_t first = std::min(n, capacity_ - start);
        std::copy(buffer_.begin() + static_cast<std::ptrdiff_t>(start),
                  buffer_.begin() + static_cast<std::ptrdiff_t>(start + first), out);
        std::copy(buffer_.begin(), buffer_.begin() + static_cast<std::ptrdiff_t>(n - first), out + first);
        return n;
    }

    // Consumer. Drops up to count elements.
    size_t skip(size_t count) {
        const size_t r = read_.load(std::memory_order_relaxed);
        const size_t w = write_.load(std::memory_order_acquire);
        const size_t n = std::min(count, w - r);
        read_.store(r + n, std::memory_order_release);
        totalRead_ += n;
        return n;
    }

    // 64-bit stream positions. framesWritten() belongs to the producer, framesRead() to the consumer.
    int64_t framesWritten() const { return static_cast<int64_t>(totalWritten_); }
    int64_t framesRead() const { return static_cast<int64_t>(totalRead_); }

    // Not thread-safe: only call while neither side is active.
    void reset() {
        write_.store(0, std::memory_order_relaxed);
        read_.store(0, std::memory_order_relaxed);
        totalWritten_ = 0;
        totalRead_ = 0;
    }

private:
    static size_t nextPowerOfTwo(size_t v) {
        size_t p = 1;
        while (p < v) p <<= 1;
        return p;
    }

    const size_t capacity_;
    const size_t mask_;
    std::vector<T> buffer_;
    alignas(64) std::atomic<size_t> write_{0};
    alignas(64) std::atomic<size_t> read_{0};
    uint64_t totalWritten_ = 0;  // producer-owned
    uint64_t totalRead_ = 0;     // consumer-owned
};

}  // namespace voiceshift::dsp
