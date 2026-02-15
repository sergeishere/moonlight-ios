//
//  AudioRingBuffer.h
//  Moonlight
//
//  SPSC (Single-Producer Single-Consumer) lock-free ring buffer for audio.
//  Safe for use between a network receive thread (producer) and an
//  AudioUnit render callback (consumer) without any locks or allocations.
//

#ifndef AudioRingBuffer_h
#define AudioRingBuffer_h

#include <stdint.h>
#include <stdatomic.h>

typedef struct {
    float *buffer;
    uint32_t capacitySamples; // total capacity in samples (frames * channels), power-of-2
    uint32_t mask;            // capacitySamples - 1, for bitwise AND
    _Atomic uint32_t head;    // written only by producer
    _Atomic uint32_t tail;    // written only by consumer
} AudioRingBuffer;

// Initialize ring buffer with capacity for `frames` frames of `channels` channels.
// Actual capacity is rounded up to the next power-of-2 in samples.
// Returns 0 on success, -1 on failure.
int AudioRingBuffer_Init(AudioRingBuffer *rb, uint32_t frames, uint32_t channels);

// Free the ring buffer's internal storage.
void AudioRingBuffer_Destroy(AudioRingBuffer *rb);

// Write `frames` interleaved frames into the ring buffer.
// Returns the number of frames actually written (may be less if buffer is full).
uint32_t AudioRingBuffer_Write(AudioRingBuffer *rb, const float *data, uint32_t frames, uint32_t channels);

// Read `frames` interleaved frames from the ring buffer into `out`.
// Returns the number of frames actually read (may be less if buffer doesn't have enough data).
uint32_t AudioRingBuffer_Read(AudioRingBuffer *rb, float *out, uint32_t frames, uint32_t channels);

// Returns the number of frames available for reading.
uint32_t AudioRingBuffer_AvailableRead(const AudioRingBuffer *rb, uint32_t channels);

// Reset the ring buffer (not thread-safe — call only when no producer/consumer is active).
void AudioRingBuffer_Reset(AudioRingBuffer *rb);

#endif /* AudioRingBuffer_h */
