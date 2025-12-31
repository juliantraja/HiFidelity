# Find Similar Tracks Feature

## Overview

This feature allows users to find tracks similar to the currently playing track based on:
- **Musical Key** (Camelot System): Finds tracks with compatible keys for DJ-style mixing
- **BPM (Beats Per Minute)**: Finds tracks with similar tempo (±5 BPM by default)

## Implementation Status

### ✅ Completed

1. **Camelot Key System**
   - Added `CamelotKey` utility class (`HiFidelity/Utils/CamelotKey.swift`)
   - Converts standard key notation (0-11, mode 0/1) to Camelot Wheel notation (1A-12A for minor, 1B-12B for major)
   - Includes compatibility checking for adjacent and relative keys

2. **Database Schema**
   - Added `camelot_key` field to `song_features` table
   - Created database migration (v7_camelot_key)
   - Migration automatically populates Camelot keys for existing records

3. **Model Updates**
   - Added `camelotKey: String?` field to `SongFeatures` model
   - Added helper methods: `deriveCamelotKey()` and `getCamelotKey()`

4. **Similarity Search Functions**
   - `findTracksByCamelotKey()`: Find tracks by compatible Camelot keys
   - `findTracksByBPM()`: Find tracks with similar BPM (±5 BPM tolerance)
   - `findSimilarTracksByKeyAndBPM()`: Combined search using both criteria

5. **UI Components**
   - Added "Find Similar" button in `TrackInfoDisplay` (next to favorite button)
   - Added filtering state to `TracksTabView` to show similar tracks
   - Added "Clear Similar" button when similar tracks filter is active

### ⚠️ Pending

1. **Audio Analysis Service**
   - Need to implement automatic extraction of BPM and key from audio files
   - Currently relies on metadata tags (which may not always be present)
   - Suggested approach:
     - Use audio analysis libraries (e.g., Essentia, librosa, or BASS analysis functions)
     - Extract tempo/BPM using beat detection algorithms
     - Extract key using chromagram analysis or pitch class profile
     - Store results in `song_features` table

2. **Metadata Display**
   - Add Camelot key and BPM display in track table views
   - Show key/BPM in track info panels
   - Add columns to track table for key and BPM

## Usage

1. **Finding Similar Tracks**
   - Play a track
   - Click the "Find Similar" button (waveform icon) next to the favorite button in the playback bar
   - The tracks view will filter to show similar tracks based on key and BPM

2. **Clearing the Filter**
   - Click "Clear Similar" button in the tracks toolbar
   - Or select a different filter from the dropdown menu

## Technical Details

### Camelot Wheel Mapping

The Camelot Wheel maps musical keys to numbers for easy DJ mixing:
- **Minor keys (A)**: 1A-12A
- **Major keys (B)**: 1B-12B

Compatible keys for mixing:
- Same key (perfect match)
- Adjacent keys (±1 on the wheel)
- Relative major/minor (same number, opposite mode)

### BPM Matching

Default tolerance: ±5 BPM
- Can be adjusted in `findTracksByBPM()` function
- Searches both `song_features.tempo` and `tracks.bpm` fields

### Database Queries

The similarity search functions use efficient database queries with indexes:
- Index on `camelot_key` for fast key-based searches
- Index on `tempo` for BPM-based searches
- Combined queries for key + BPM matching

## Future Enhancements

1. **Advanced Similarity**
   - Add energy, valence, and other audio features to similarity calculation
   - Weight different criteria (e.g., 70% key, 30% BPM)
   - Allow user to customize similarity parameters

2. **Batch Analysis**
   - Background service to analyze all tracks in library
   - Progress indicator for analysis
   - Settings to control analysis behavior

3. **Smart Playlists**
   - Create playlists based on similar tracks
   - Auto-generate DJ sets with compatible keys and BPM

4. **Visualization**
   - Show Camelot Wheel in UI
   - Visualize key relationships
   - BPM timeline/graph

## Notes

- The feature requires tracks to have `song_features` records with key and BPM data
- If a track doesn't have features, the search will fall back to metadata tags (`tracks.bpm`)
- The Camelot key is automatically derived from key/mode if not explicitly set

