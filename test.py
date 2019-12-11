#!./venv/bin/python3
# -*- coding: utf-8 -*-

import unittest
from cheetah import Album


class TestSong(unittest.TestCase):


    def test_fake_path_fails(self):
        with self.assertRaises(Exception) as context:
            Album('/tmp/fake_path')

        self.assertTrue('Path does not exist' in str(context.exception))


if __name__ == '__main__':
    unittest.main()
