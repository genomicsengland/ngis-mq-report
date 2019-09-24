import json
import os

def getProfile(f = os.path.expanduser(".gel_config"), items = None):
    """Get GEL profile details from file. See https://cnfl.extge.co.uk/pages/viewpage.action?pageId=113196964 for details
    f - location of config file, default is ~/.gel_config
    items - str or list of first-level items to return"""
    # get file contents
    with open(f) as json_file:
        d = json.load(json_file)
    # filter out the items from the object (including .defaults)
    if items is not None:
        if type(items) is str:
            items = [items]
        d = {k: v for k, v in d.items() if k in items or k == '.defaults'}
    # do the default replacement
    replaceDefaults(d)
    # if only asked for a single item, just give that, otherwise return the whole dict
    if items is not None and len(items) == 1:
        return d[items[0]]
    else:
        return d


def recursiveSearchReplace(x, s, r):
    """Function to recursively search and replace within a dictionary"""
    for k, v in x.items():
        if type(v) is dict:
            recursiveSearchReplace(v, s, r)
        else:
            if v == s:
                x[k] = r


def replaceDefaults(d):
    """Search and replace defaults in config dictionary, removes defaults section in the process"""
    defaults = d.pop('.defaults')
    for k, v in defaults.items():
        recursiveSearchReplace(d, '!' + k + '!', v)

