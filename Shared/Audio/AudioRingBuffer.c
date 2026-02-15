//
//  AudioRingBuffer.c
//  Moonlight
//
//  SPSC lock-free ring buffer implementation using stdatomic.
//  memory_order_acquire/release for head/tail synchronization.
//

#include "AudioRingBuffer.h"
#include <stdlib.h>
#include <string.h>

static uint32_t nextPowerOf2(uint32_t v) {
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
}

int AudioRingBuffer_Init(AudioRingBuffer *rb, uint32_t frames, uint32_t channels) {
    uint32_t requestedSamples = frames * channels;
    uint32_t capacity = nextPowerOf2(requestedSamples);

    // Minimum capacity sanity check
    if (capacity < 64) {
        capacity = 64;
    }

    rb->buffer = (float *)calloc(capacity, sizeof(float));
    if (rb->buffer == NULL) {
        return -1;
    }

    rb->capacitySamples = capacity;
    rb->mask = capacity - 1;
    atomic_store_explicit(&rb->head, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->tail, 0, memory_order_relaxed);

    return 0;
}

void AudioRingBuffer_Destroy(AudioRingBuffer *rb) {
    if (rb->buffer != NULL) {
        free(rb->buffer);
        rb->buffer = NULL;
    }
    rb->capacitySamples = 0;
    rb->mask = 0;
}

uint32_t AudioRingBuffer_Write(AudioRingBuffer *rb, const float *data, uint32_t frames, uint32_t channels) {
    uint32_t samplesToWrite = frames * channels;

    uint32_t head = atomic_load_explicit(&rb->head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);

    uint32_t available = rb->capacitySamples - (head - tail);
    if (samplesToWrite > available) {
        // Not enough space — drop the incoming frame entirely
        return 0;
    }

    uint32_t headIndex = head & rb->mask;
    uint32_t firstChunk = rb->capacitySamples - headIndex;

    if (firstChunk >= samplesToWrite) {
        memcpy(rb->buffer + headIndex, data, samplesToWrite * sizeof(float));
    } else {
        memcpy(rb->buffer + headIndex, data, firstChunk * sizeof(float));
        memcpy(rb->buffer, data + firstChunk, (samplesToWrite - firstChunk) * sizeof(float));
    }

    atomic_store_explicit(&rb->head, head + samplesToWrite, memory_order_release);
    return frames;
}

uint32_t AudioRingBuffer_Read(AudioRingBuffer *rb, float *out, uint32_t frames, uint32_t channels) {
    uint32_t samplesToRead = frames * channels;

    uint32_t tail = atomic_load_explicit(&rb->tail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&rb->head, memory_order_acquire);

    uint32_t availableSamples = head - tail;
    if (availableSamples < samplesToRead) {
        // Return only full frames
        uint32_t availableFrames = availableSamples / channels;
        samplesToRead = availableFrames * channels;
        frames = availableFrames;
    }

    if (samplesToRead == 0) {
        return 0;
    }

    uint32_t tailIndex = tail & rb->mask;
    uint32_t firstChunk = rb->capacitySamples - tailIndex;

    if (firstChunk >= samplesToRead) {
        memcpy(out, rb->buffer + tailIndex, samplesToRead * sizeof(float));
    } else {
        memcpy(out, rb->buffer + tailIndex, firstChunk * sizeof(float));
        memcpy(out + firstChunk, rb->buffer,
               (samplesToRead - firstChunk) * sizeof(float));
    }

    atomic_store_explicit(&rb->tail, tail + samplesToRead, memory_order_release);
    return frames;
}

uint32_t AudioRingBuffer_AvailableRead(const AudioRingBuffer *rb, uint32_t channels) {
    uint32_t head = atomic_load_explicit(&rb->head, memory_order_acquire);
    uint32_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);
    uint32_t availableSamples = head - tail;
    return availableSamples / channels;
}

void AudioRingBuffer_Reset(AudioRingBuffer *rb) {
    atomic_store_explicit(&rb->head, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->tail, 0, memory_order_relaxed);
}
