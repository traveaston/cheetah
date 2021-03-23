#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import re as regex
import sys
import mutagen

NAME = 'cheetah'
VERSION = '2.0.3'
DESCRIPTION = 'Audio transcoding tool'
AUTHOR = 'Trav Easton'
AUTHOR_EMAIL = 'travzdevil69@hotmail.com'
URL = 'https://github.com/traveaston/cheetah'
LICENSE = 'MIT'
ZIP_SAFE = True


def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument('source', default='',
                        help='Source to transcode from')
    parser.add_argument('-b', '--bitrate', default='V0',
                        help='Bitrate to transcode to (default: V0)')
    parser.add_argument('-o', '--output_path', default='',
                        help='Specify full output path with new folder title')
    parser.add_argument('-O', '--relocate_path', default='',
                        help='Relocate album to path but keep default name')
    parser.add_argument('-n', '--dry-run', default=False, action='store_true',
                        help='Show what would happen and exit')
    parser.add_argument('-r', '--raw-tags', default=False, action='store_true',
                        help='Show raw tags and exit')

    return parser.parse_args()


class Cheetah:
    def __init__(self, args):
        super(Cheetah, self).__init__()

        self.args = args

        self.source, self.output_path = self.build_paths(self.args)

        self.transcode_complete = False

        self.source_type = self.get_source_type()

        if self.source_type == 'folder':
            self.album = Album(self)
        else:
            logging.error('Can\'t transcode single song yet sorry')
            sys.exit()


    def transcode(self):
        print("Transcode placeholder")

        self.transcode_complete = True


    def build_paths(self, args):
        """Get/generate source and output paths"""

        # Strip both forward and backslashes because copying the path from
        # Windows explorer or similar isn't unreasonable user behaviour
        source = args.source.rstrip('/\\')

        # Substitute original format for new format in album directory name
        new_folder_title = regex.sub(r'FLAC', args.bitrate, source)

        # Prefer full output path, then relocation path, then default to CWD
        if args.output_path:
            output_path = args.output_path
        elif args.relocate_path:
            output_path = '{}/{}'.format(
                args.relocate_path.rstrip('/\\'),
                new_folder_title)
        else:
            output_path = f'{os.getcwd()}/{new_folder_title}'

        return source, output_path


    def get_source_type(self):
        if os.path.isfile(self.source):
            return 'file'

        if os.path.isdir(self.source):
            return 'folder'

        # Symlinks?
        raise Exception(f'"{self.source}" is not a file or folder')


class Album:
    def __init__(self, cheetah):
        super(Album, self).__init__()

        self.cheetah = cheetah
        self.source = self.cheetah.source

        self.song_files, self.cover_files = self.detect_songs_and_covers()
        self.totaltracks = len(self.song_files)

        self.songs = self.instantiate_songs(self.song_files)


    def detect_songs_and_covers(self):
        song_files = []
        covers = []

        for root, dummy, files in os.walk(self.source):
            for file in files:
                if file.endswith(".flac"):
                    song_files.append(os.path.join(root, file))
                if file.endswith(".jpg"):
                    covers.append(os.path.join(root, file))

        return sorted(song_files), covers


    def instantiate_songs(self, song_files):
        songs = []

        for file in song_files:
            songs.append(Song(file, self))

        return songs


class Song:
    def __init__(self, source, album):
        super(Song, self).__init__()

        self.album = album

        self.source = source

        self.tags = {}

        self.raw_tags = mutagen.File(self.source)

        if album.cheetah.args.raw_tags:
            print(self.raw_tags)


    def __str__(self):
        return str(self.tags)


def main():
    args = parse_args()

    if args.raw_tags:
        args.dry_run = True

    cheetah = Cheetah(args)

    if args.dry_run:
        print(*cheetah.album.songs, sep='\n')
    else:
        cheetah.transcode()


if __name__ == '__main__':
    main()
