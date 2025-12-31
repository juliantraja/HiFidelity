//
//  TagLibMetadataWriter.mm
//  HiFidelity
//
//  Objective-C++ implementation for writing metadata using TagLib
//

#import <Foundation/Foundation.h>

// TagLib C++ headers
#include "taglib/fileref.h"
#include "taglib/tag.h"
#include "taglib/tstring.h"

// Format-specific headers
#include "taglib/mpegfile.h"
#include "taglib/id3v2tag.h"
#include "taglib/id3v2frame.h"
#include "taglib/textidentificationframe.h"
#include "taglib/attachedpictureframe.h"

#include "taglib/mp4file.h"
#include "taglib/mp4tag.h"
#include "taglib/mp4item.h"
#include "taglib/mp4coverart.h"

#include "taglib/flacfile.h"
#include "taglib/flacpicture.h"
#include "taglib/xiphcomment.h"

#include "taglib/vorbisfile.h"
#include "taglib/opusfile.h"

// Convert NSString to TagLib::String
static TagLib::String NSStringToTagString(NSString* str) {
    if (!str || str.length == 0) {
        return TagLib::String();
    }
    return TagLib::String([str UTF8String], TagLib::String::UTF8);
}

// Convert NSInteger to unsigned int (for year, track number, etc.)
static unsigned int NSIntegerToUInt(NSInteger value) {
    if (value <= 0) {
        return 0;
    }
    return static_cast<unsigned int>(value);
}

// Write metadata to file using TagLib
extern "C" BOOL WriteMetadataToFile(NSURL* fileURL, NSDictionary<NSString*, id>* metadata, NSError** error) {
    if (!fileURL || !metadata) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataWriter"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid file URL or metadata"}];
        }
        return NO;
    }
    
    const char* filePath = [fileURL.path UTF8String];
    std::string ext = [[fileURL.pathExtension lowercaseString] UTF8String];
    
    // Handle format-specific metadata
    BOOL success = NO;
    
    // MP3
    if (ext == "mp3") {
        TagLib::MPEG::File mpegFile(filePath);
        if (mpegFile.isValid()) {
            TagLib::ID3v2::Tag* id3v2Tag = mpegFile.ID3v2Tag(true); // Create if doesn't exist
            
            // Write basic tag fields
            if (metadata[@"title"]) {
                id3v2Tag->setTitle(NSStringToTagString(metadata[@"title"]));
            }
            if (metadata[@"artist"]) {
                id3v2Tag->setArtist(NSStringToTagString(metadata[@"artist"]));
            }
            if (metadata[@"album"]) {
                id3v2Tag->setAlbum(NSStringToTagString(metadata[@"album"]));
            }
            if (metadata[@"genre"]) {
                id3v2Tag->setGenre(NSStringToTagString(metadata[@"genre"]));
            }
            if (metadata[@"year"]) {
                NSString* yearStr = metadata[@"year"];
                if (yearStr && yearStr.length > 0) {
                    NSInteger year = [yearStr integerValue];
                    if (year > 0) {
                        id3v2Tag->setYear(NSIntegerToUInt(year));
                    }
                }
            }
            if (metadata[@"trackNumber"]) {
                NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                if (trackNum > 0) {
                    id3v2Tag->setTrack(NSIntegerToUInt(trackNum));
                }
            }
            
            if (id3v2Tag) {
                // Write additional ID3v2 fields using TextIdentificationFrame
                if (metadata[@"albumArtist"]) {
                    // Remove existing TPE2 frames
                    TagLib::ID3v2::FrameList tpe2Frames = id3v2Tag->frameList("TPE2");
                    for (auto it = tpe2Frames.begin(); it != tpe2Frames.end(); ++it) {
                        id3v2Tag->removeFrame(*it);
                    }
                    // Add new TPE2 frame (Album Artist)
                    TagLib::ID3v2::TextIdentificationFrame* tpe2Frame = new TagLib::ID3v2::TextIdentificationFrame("TPE2", TagLib::String::Latin1);
                    tpe2Frame->setText(NSStringToTagString(metadata[@"albumArtist"]));
                    id3v2Tag->addFrame(tpe2Frame);
                }
                if (metadata[@"composer"]) {
                    // Remove existing TCOM frames
                    TagLib::ID3v2::FrameList tcomFrames = id3v2Tag->frameList("TCOM");
                    for (auto it = tcomFrames.begin(); it != tcomFrames.end(); ++it) {
                        id3v2Tag->removeFrame(*it);
                    }
                    // Add new TCOM frame (Composer)
                    TagLib::ID3v2::TextIdentificationFrame* tcomFrame = new TagLib::ID3v2::TextIdentificationFrame("TCOM", TagLib::String::Latin1);
                    tcomFrame->setText(NSStringToTagString(metadata[@"composer"]));
                    id3v2Tag->addFrame(tcomFrame);
                }
                
                // Handle artwork: add new or remove existing
                if (metadata[@"removeArtwork"]) {
                    // Explicitly remove all artwork frames
                    TagLib::ID3v2::FrameList pictureFrames = id3v2Tag->frameList("APIC");
                    for (auto it = pictureFrames.begin(); it != pictureFrames.end(); ++it) {
                        id3v2Tag->removeFrame(*it);
                    }
                } else if (metadata[@"artworkData"]) {
                    NSData* artworkData = metadata[@"artworkData"];
                    if (artworkData && artworkData.length > 0) {
                        // Remove existing artwork frames
                        TagLib::ID3v2::FrameList pictureFrames = id3v2Tag->frameList("APIC");
                        for (auto it = pictureFrames.begin(); it != pictureFrames.end(); ++it) {
                            id3v2Tag->removeFrame(*it);
                        }
                        
                        // Add new artwork frame
                        TagLib::ID3v2::AttachedPictureFrame* pictureFrame = new TagLib::ID3v2::AttachedPictureFrame();
                        pictureFrame->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
                        pictureFrame->setMimeType("image/jpeg");
                        pictureFrame->setPicture(TagLib::ByteVector((const char*)[artworkData bytes], (unsigned int)artworkData.length));
                        id3v2Tag->addFrame(pictureFrame);
                    }
                }
            }
            
            success = mpegFile.save();
        }
    }
    // MP4/M4A
    else if (ext == "m4a" || ext == "m4b" || ext == "m4p" || ext == "mp4") {
        TagLib::MP4::File mp4File(filePath);
        if (mp4File.isValid()) {
            TagLib::MP4::Tag* mp4Tag = mp4File.tag();
            if (mp4Tag) {
                // Write basic tag fields
                if (metadata[@"title"]) {
                    mp4Tag->setTitle(NSStringToTagString(metadata[@"title"]));
                }
                if (metadata[@"artist"]) {
                    mp4Tag->setArtist(NSStringToTagString(metadata[@"artist"]));
                }
                if (metadata[@"album"]) {
                    mp4Tag->setAlbum(NSStringToTagString(metadata[@"album"]));
                }
                if (metadata[@"genre"]) {
                    mp4Tag->setGenre(NSStringToTagString(metadata[@"genre"]));
                }
                if (metadata[@"year"]) {
                    NSString* yearStr = metadata[@"year"];
                    if (yearStr && yearStr.length > 0) {
                        NSInteger year = [yearStr integerValue];
                        if (year > 0) {
                            mp4Tag->setYear(NSIntegerToUInt(year));
                        }
                    }
                }
                if (metadata[@"trackNumber"]) {
                    NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                    if (trackNum > 0) {
                        mp4Tag->setTrack(NSIntegerToUInt(trackNum));
                    }
                }
                
                // Write additional MP4 fields
                if (metadata[@"albumArtist"]) {
                    mp4Tag->setItem("aART", TagLib::StringList(NSStringToTagString(metadata[@"albumArtist"])));
                }
                if (metadata[@"composer"]) {
                    mp4Tag->setItem("\251wrt", TagLib::StringList(NSStringToTagString(metadata[@"composer"])));
                }
                
                // Handle artwork: add new or remove existing
                if (metadata[@"removeArtwork"]) {
                    // Explicitly remove artwork by setting empty list
                    TagLib::MP4::CoverArtList emptyList;
                    mp4Tag->setItem("covr", emptyList);
                } else if (metadata[@"artworkData"]) {
                    NSData* artworkData = metadata[@"artworkData"];
                    if (artworkData && artworkData.length > 0) {
                        TagLib::MP4::CoverArt coverArt(TagLib::MP4::CoverArt::JPEG, 
                                                       TagLib::ByteVector((const char*)[artworkData bytes], (unsigned int)artworkData.length));
                        TagLib::MP4::CoverArtList coverArtList;
                        coverArtList.append(coverArt);
                        mp4Tag->setItem("covr", coverArtList);
                    }
                }
            }
            success = mp4File.save();
        }
    }
    // FLAC
    else if (ext == "flac") {
        TagLib::FLAC::File flacFile(filePath);
        if (flacFile.isValid()) {
            TagLib::Ogg::XiphComment* xiphComment = flacFile.xiphComment(true); // Create if doesn't exist
            if (xiphComment) {
                // Write basic tag fields
                if (metadata[@"title"]) {
                    xiphComment->addField("TITLE", NSStringToTagString(metadata[@"title"]), true);
                }
                if (metadata[@"artist"]) {
                    xiphComment->addField("ARTIST", NSStringToTagString(metadata[@"artist"]), true);
                }
                if (metadata[@"album"]) {
                    xiphComment->addField("ALBUM", NSStringToTagString(metadata[@"album"]), true);
                }
                if (metadata[@"genre"]) {
                    xiphComment->addField("GENRE", NSStringToTagString(metadata[@"genre"]), true);
                }
                if (metadata[@"year"]) {
                    NSString* yearStr = metadata[@"year"];
                    if (yearStr && yearStr.length > 0) {
                        xiphComment->addField("DATE", NSStringToTagString(yearStr), true);
                    }
                }
                if (metadata[@"trackNumber"]) {
                    NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                    if (trackNum > 0) {
                        NSString* trackNumStr = [NSString stringWithFormat:@"%ld", (long)trackNum];
                        xiphComment->addField("TRACKNUMBER", NSStringToTagString(trackNumStr), true);
                    }
                }
                
                if (metadata[@"albumArtist"]) {
                    xiphComment->addField("ALBUMARTIST", NSStringToTagString(metadata[@"albumArtist"]), true);
                }
                if (metadata[@"composer"]) {
                    xiphComment->addField("COMPOSER", NSStringToTagString(metadata[@"composer"]), true);
                }
                
                // Handle artwork: add new or remove existing
                if (metadata[@"removeArtwork"]) {
                    // Explicitly remove all pictures
                    TagLib::List<TagLib::FLAC::Picture*> pictures = flacFile.pictureList();
                    for (auto* picture : pictures) {
                        delete picture;
                    }
                    flacFile.removePictures();
                } else if (metadata[@"artworkData"]) {
                    NSData* artworkData = metadata[@"artworkData"];
                    if (artworkData && artworkData.length > 0) {
                        // Remove existing pictures
                        TagLib::List<TagLib::FLAC::Picture*> pictures = flacFile.pictureList();
                        for (auto* picture : pictures) {
                            delete picture;
                        }
                        flacFile.removePictures();
                        
                        // Add new picture
                        TagLib::FLAC::Picture* picture = new TagLib::FLAC::Picture();
                        picture->setType(TagLib::FLAC::Picture::FrontCover);
                        picture->setMimeType("image/jpeg");
                        picture->setData(TagLib::ByteVector((const char*)[artworkData bytes], (unsigned int)artworkData.length));
                        flacFile.addPicture(picture);
                    }
                }
            }
            success = flacFile.save();
        }
    }
    // Ogg Vorbis
    else if (ext == "ogg") {
        TagLib::Vorbis::File vorbisFile(filePath);
        if (vorbisFile.isValid()) {
            TagLib::Ogg::XiphComment* xiphComment = vorbisFile.tag();
            if (xiphComment) {
                // Write basic tag fields
                if (metadata[@"title"]) {
                    xiphComment->addField("TITLE", NSStringToTagString(metadata[@"title"]), true);
                }
                if (metadata[@"artist"]) {
                    xiphComment->addField("ARTIST", NSStringToTagString(metadata[@"artist"]), true);
                }
                if (metadata[@"album"]) {
                    xiphComment->addField("ALBUM", NSStringToTagString(metadata[@"album"]), true);
                }
                if (metadata[@"genre"]) {
                    xiphComment->addField("GENRE", NSStringToTagString(metadata[@"genre"]), true);
                }
                if (metadata[@"year"]) {
                    NSString* yearStr = metadata[@"year"];
                    if (yearStr && yearStr.length > 0) {
                        xiphComment->addField("DATE", NSStringToTagString(yearStr), true);
                    }
                }
                if (metadata[@"trackNumber"]) {
                    NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                    if (trackNum > 0) {
                        NSString* trackNumStr = [NSString stringWithFormat:@"%ld", (long)trackNum];
                        xiphComment->addField("TRACKNUMBER", NSStringToTagString(trackNumStr), true);
                    }
                }
                
                if (metadata[@"albumArtist"]) {
                    xiphComment->addField("ALBUMARTIST", NSStringToTagString(metadata[@"albumArtist"]), true);
                }
                if (metadata[@"composer"]) {
                    xiphComment->addField("COMPOSER", NSStringToTagString(metadata[@"composer"]), true);
                }
            }
            success = vorbisFile.save();
        }
    }
    // Opus
    else if (ext == "opus") {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (opusFile.isValid()) {
            TagLib::Ogg::XiphComment* xiphComment = opusFile.tag();
            if (xiphComment) {
                // Write basic tag fields
                if (metadata[@"title"]) {
                    xiphComment->addField("TITLE", NSStringToTagString(metadata[@"title"]), true);
                }
                if (metadata[@"artist"]) {
                    xiphComment->addField("ARTIST", NSStringToTagString(metadata[@"artist"]), true);
                }
                if (metadata[@"album"]) {
                    xiphComment->addField("ALBUM", NSStringToTagString(metadata[@"album"]), true);
                }
                if (metadata[@"genre"]) {
                    xiphComment->addField("GENRE", NSStringToTagString(metadata[@"genre"]), true);
                }
                if (metadata[@"year"]) {
                    NSString* yearStr = metadata[@"year"];
                    if (yearStr && yearStr.length > 0) {
                        xiphComment->addField("DATE", NSStringToTagString(yearStr), true);
                    }
                }
                if (metadata[@"trackNumber"]) {
                    NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                    if (trackNum > 0) {
                        NSString* trackNumStr = [NSString stringWithFormat:@"%ld", (long)trackNum];
                        xiphComment->addField("TRACKNUMBER", NSStringToTagString(trackNumStr), true);
                    }
                }
                
                if (metadata[@"albumArtist"]) {
                    xiphComment->addField("ALBUMARTIST", NSStringToTagString(metadata[@"albumArtist"]), true);
                }
                if (metadata[@"composer"]) {
                    xiphComment->addField("COMPOSER", NSStringToTagString(metadata[@"composer"]), true);
                }
            }
            success = opusFile.save();
        }
    }
    // For other formats, use generic FileRef
    else {
        TagLib::FileRef fileRef(filePath);
        if (!fileRef.isNull() && fileRef.tag()) {
            TagLib::Tag* tag = fileRef.tag();
            // Write basic tag fields
            if (metadata[@"title"]) {
                tag->setTitle(NSStringToTagString(metadata[@"title"]));
            }
            if (metadata[@"artist"]) {
                tag->setArtist(NSStringToTagString(metadata[@"artist"]));
            }
            if (metadata[@"album"]) {
                tag->setAlbum(NSStringToTagString(metadata[@"album"]));
            }
            if (metadata[@"genre"]) {
                tag->setGenre(NSStringToTagString(metadata[@"genre"]));
            }
            if (metadata[@"year"]) {
                NSString* yearStr = metadata[@"year"];
                if (yearStr && yearStr.length > 0) {
                    NSInteger year = [yearStr integerValue];
                    if (year > 0) {
                        tag->setYear(NSIntegerToUInt(year));
                    }
                }
            }
            if (metadata[@"trackNumber"]) {
                NSInteger trackNum = [metadata[@"trackNumber"] integerValue];
                if (trackNum > 0) {
                    tag->setTrack(NSIntegerToUInt(trackNum));
                }
            }
            success = fileRef.save();
        }
    }
    
    if (!success && error) {
        *error = [NSError errorWithDomain:@"TagLibMetadataWriter"
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to save metadata to file"}];
    }
    
    return success;
}

