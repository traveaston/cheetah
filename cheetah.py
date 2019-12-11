#!./venv/bin/python3
# -*- coding: utf-8 -*-

import argparse
import os
import re
import sys

NAME = 'cheetah'
VERSION = '2.0.0'
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

    return parser.parse_args()


def build_paths(args):
    """Get/generate source and output paths"""

    # Strip both forward and backslashes because copying the path from
    # Windows explorer or similar isn't unreasonable user behaviour
    source = args.source.rstrip('/\\')

    # Substitute original format for new format in album directory name
    new_folder_title = re.sub('FLAC', args.bitrate, source)

    # Prefer full output path, then relocation path, then default to CWD
    if args.output_path:
        output_path = args.output_path
    elif args.relocate_path:
        output_path = '{}/{}'.format(
            args.relocate_path.rstrip('/\\'),
            new_folder_title)
    else:
        output_path = '{}/{}'.format(os.getcwd(), new_folder_title)

    return source, output_path


class Album():


    def __init__(self, source):
        super(Album, self).__init__()
        self.source = source

        self.ensure_exists()

        self.song_files, self.cover_files = self.detect_songs_and_covers()
        self.total_tracks = len(self.song_files)


    def ensure_exists(self):
        if not os.path.exists(self.source):
            raise Exception('Path does not exist: {}'.format(self.source))


    def detect_songs_and_covers(self):
        song_files = []
        covers = []

        for root, dummy, files in os.walk(self.source):
            for file in files:
                if file.endswith(".flac"):
                    song_files.append(os.path.join(root, file))
                if file.endswith(".jpg"):
                    covers.append(os.path.join(root, file))

        if not covers:
            covers.append('fake_cover.jpg')

        return sorted(song_files), covers


def main():
    args = parse_args()

    source, output_path = build_paths(args)

    try:
        album = Album(source)
    except Exception as e:
        sys.exit(e)


if __name__ == '__main__':
    main()
