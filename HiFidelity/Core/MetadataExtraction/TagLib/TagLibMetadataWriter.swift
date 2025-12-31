//
//  TagLibMetadataWriter.swift
//  HiFidelity
//
//  Swift wrapper for TagLib metadata writing
//

import Foundation

/// Swift wrapper for writing metadata to audio files using TagLib
struct TagLibMetadataWriter {
    
    /// Write metadata to an audio file
    /// - Parameters:
    ///   - url: URL to the audio file
    ///   - metadata: Dictionary containing metadata fields to write
    /// - Returns: true if successful, false otherwise
    /// - Throws: Error if writing fails
    static func writeMetadata(to url: URL, metadata: [String: Any]) throws {
        var error: NSError?
        let nsURL = url as NSURL
        let success = WriteMetadataToFile(nsURL, metadata as NSDictionary, &error)
        
        if !success {
            throw error ?? NSError(domain: "TagLibMetadataWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to write metadata"])
        }
    }
    
    /// Write track metadata to file
    /// - Parameters:
    ///   - url: URL to the audio file
    ///   - track: Track object containing metadata to write
    /// - Throws: Error if writing fails
    static func writeTrackMetadata(to url: URL, track: Track) throws {
        var metadata: [String: Any] = [:]

        // Core metadata - Always write these fields even if they might be default values
        // Only skip if completely empty
        if !track.title.isEmpty && track.title != "Unknown Title" {
            metadata["title"] = track.title
        }
        if !track.artist.isEmpty && track.artist != "Unknown Artist" {
            metadata["artist"] = track.artist
        }
        if !track.album.isEmpty && track.album != "Unknown Album" {
            metadata["album"] = track.album
        }
        if !track.genre.isEmpty && track.genre != "Unknown Genre" {
            metadata["genre"] = track.genre
        }
        if !track.year.isEmpty && track.year != "Unknown Year" {
            metadata["year"] = track.year
        }
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            metadata["albumArtist"] = albumArtist
        }
        if !track.composer.isEmpty && track.composer != "Unknown Composer" {
            metadata["composer"] = track.composer
        }
        if let trackNumber = track.trackNumber {
            metadata["trackNumber"] = trackNumber
        }

        // Artwork - include nil to explicitly remove artwork
        if let artworkData = track.artworkData {
            metadata["artworkData"] = artworkData
        } else {
            // Explicitly mark artwork for removal
            metadata["removeArtwork"] = true
        }

        Logger.debug("Writing metadata to file: \(url.lastPathComponent) - metadata keys: \(metadata.keys.joined(separator: ", "))")

        try writeMetadata(to: url, metadata: metadata)
    }
}

// C function declaration
@_silgen_name("WriteMetadataToFile")
func WriteMetadataToFile(_ fileURL: NSURL, _ metadata: NSDictionary, _ error: UnsafeMutablePointer<NSError?>) -> Bool

