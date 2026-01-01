# Audio Analysis Implementation Guide

## Overview

This guide explains how to implement BPM and key analysis during library
import. The implementation uses **Accelerate framework** (built into macOS)
for signal processing.

## Architecture

### Components

1. **AudioFeatureAnalyzer.swift** - Core analysis engine
   - Uses Accelerate for FFT and signal processing
   - Extracts BPM using autocorrelation
   - Extracts key using chromagram analysis

2. **AudioAnalysisService.swift** - Service layer
   - Manages analysis queue
   - Integrates with database
   - Handles background processing

3. **Integration Point** - `DBTrack.swift`
   - Automatically queues tracks for analysis after import
   - Runs in background (doesn't block import)

## How It Works

### During Import

1. **Track is imported** → Metadata extracted via TagLib
2. **Track saved to database** → Gets track ID
3. **Analysis queued** → `AudioAnalysisService.queueForAnalysis()` called
4. **Background processing** → Analyzer processes queue asynchronously
5. **Features saved** → Results stored in `song_features` table

### Analysis Process

1. **Load Audio**: Uses AVFoundation to load audio file
2. **Convert to Mono**: Downmix to single channel for analysis
3. **BPM Detection**:
   - Apply high-pass filter
   - Calculate autocorrelation
   - Find peaks (correspond to tempo)
   - Convert to BPM
4. **Key Detection**:
   - Calculate chromagram (pitch class profile)
   - Match against key profiles (Krumhansl-Schmuckler)
   - Determine key and mode (major/minor)
5. **Store Results**: Save to `song_features` with Camelot key

## Current Status

✅ **Code Created**: Analysis service and analyzer are implemented
⚠️ **Needs Testing**: FFT implementation may need refinement
⚠️ **Performance**: Analysis is CPU-intensive; runs in background

## Usage

### Automatic (During Import)

Analysis happens automatically when tracks are imported. No user action needed.

### Manual Analysis

```swift
// Analyze a specific track
let result = try await AudioAnalysisService.shared.analyzeTrack(
    trackId: trackId,
    url: track.url
)

// Analyze all tracks without features
await AudioAnalysisService.shared.analyzeAllTracksWithoutFeatures()
```

### Settings Integration

You can add a setting to enable/disable automatic analysis:

```swift
@AppStorage("enableAudioAnalysis") var enableAudioAnalysis: Bool = true
```

Then modify `DBTrack.swift`:

```swift
if enableAudioAnalysis {
    Task {
        AudioAnalysisService.shared.queueForAnalysis(trackId: trackId)
    }
}
```

## Performance Considerations

- **Analysis Time**: ~2-10 seconds per track (depends on length and CPU)
- **Background Processing**: Runs asynchronously, doesn't block UI
- **Queue Management**: Processes 2 tracks concurrently by default
- **Resource Usage**: CPU-intensive; consider limiting concurrent analysis

## Alternative Approaches

If the Accelerate-based implementation has issues, consider:

### Option 1: Use aubio (C Library)

- More accurate BPM/key detection
- Requires C bridge or Swift Package
- Better for production use

### Option 2: Use Essentia (C++ Library)

- Most accurate, industry-standard
- Requires C++ bridge
- Best for professional use

### Option 3: Use Python Bridge (librosa)

- Easiest to implement
- Requires Python runtime
- Slower but very accurate

### Option 4: Use Metadata Tags Only

- Fastest (no analysis needed)
- Relies on tags being present
- Current fallback approach

## Testing

1. **Test with known tracks**: Use tracks with known BPM/key
2. **Verify accuracy**: Compare results with manual analysis
3. **Check performance**: Monitor CPU usage during analysis
4. **Test queue**: Ensure background processing works correctly

## Troubleshooting

### Analysis fails silently

- Check logs for errors
- Verify audio file is accessible
- Check file format is supported

### Slow analysis

- Reduce concurrent analysis count
- Consider analyzing only on demand
- Use metadata tags when available

### Inaccurate results

- BPM/key detection is probabilistic
- Results improve with longer tracks
- Consider using more sophisticated algorithms

## Next Steps

1. **Test the implementation** with real audio files
2. **Refine algorithms** based on accuracy testing
3. **Add progress indicators** in UI
4. **Add settings** to control analysis behavior
5. **Optimize performance** for large libraries
