#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import re as regex
import sys
import logging
import mutagen

NAME = 'cheetah'
VERSION = '2.0.5'
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

        self.folder_artist = self.get_folder_artist()

        if self.args.dry_run:
            logging.info(f'folder_artist: {self.folder_artist}')

        self.check_source_and_output_path()

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


    def check_source_and_output_path(self):
        if not os.path.exists(self.source):
            logging.error(f'Path does not exist: "{self.source}"')
            exit()

        if os.path.exists(self.output_path) and os.listdir(self.output_path):
            confirm = input(f'Overwrite existing path: "{self.output_path}" [Y/n] ? ') or 'y'

            if confirm.lower() != 'y':
                logging.error(f'Path already exists, not overwriting')
                exit()


    def get_folder_artist(self):
        artist_regex = regex.compile(r'(^.+?) ?-')
        source_split = self.source.split('/')

        while source_split:
            match = artist_regex.match(source_split[-1])
            if match:
                logging.debug(f'Detected "{match.group(1)}" as artist from "{source_split[-1]}"')
                return match.group(1)
            source_split.pop(-1)

        logging.warning(f'Couldn\'t get artist from path: "{self.source}"')


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

        self.folder_artist = self.cheetah.folder_artist

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
        self.tags_used = []

        self.raw_tags = mutagen.File(self.source)

        if album.cheetah.args.raw_tags:
            print(self.raw_tags)

        self.get_and_format_tags()


    def __str__(self):
        return str(self.tags)


    def get_and_format_tags(self):
        self.set_tag('album')
        self.set_tag('artist')

        # let album artist fall back to artist
        self.set_tag(['album_artist', 'albumartist', 'artist'])

        self.set_tag(['year', 'date'], self.format_year)

        self.set_tag('title')
        self.set_tag('genre', self.format_genre)

        self.set_tag(['totaltracks', 'tracktotal'], int)
        self.set_tag('tracknumber')

        self.set_tag(['totaldiscs', 'disctotal'], int)
        self.set_tag('discnumber')


    def format_genre(self, genre):
        if genre == 'Rap/Hip Hop':
            return 'Hip-Hop'
        elif genre == 'R & B':
            return 'R&B'

        return genre


    def format_year(self, year):
        if len(year) != 4:
            match = regex.match(r'^\d{4}', year)
            if match:
                year = match[0]
            else:
                logging.error(f'{year} does not follow format YYYY-MM-DD')

        return year


    def set_tag(self, fields, callback = None):
        """
        fields can be a list where the first item will be used as the key, or
        just a string
        set_tag('artist') # set self.tags['artist'] to artist tag from metadata
        set_tag(['artist', 'album_artist']) # set self.tags['artist'] to
        artist tag (or album_artist if empty) from metadata
        also allow a method name to be passed as a second argument to format
        or otherwise filter metadata before saving to tags
        """

        # convert fields variable to a list if necessary
        if isinstance(fields, str):
            fields = [fields]

        tag = fields[0]

        # set tag first in case metadata is empty
        self.tags[tag] = ''
        value = ''

        # try all fields in order and return the first value found
        for key in fields:
            try:
                value = self.raw_tags[key]
            except KeyError:
                pass
            else:
                # convert lists into strings
                # TODO: this could be simplified to just the join() line
                if isinstance(value, list) and len(value) == 1:
                    value = value[0]
                else:
                    value = ', '.join(value)

                self.tags_used.append(key)
                break

        if callback and value:
            try:
                self.tags[tag] = callback(value)
            except:
                logging.error(f'Failed to set tag (using {callback}): "{tag}": "{value}"')
        else:
            self.tags[tag] = value

        return self.tags[tag]


def main():
    logging.basicConfig(level=logging.INFO)

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
