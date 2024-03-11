__version__ = "2.0"

import json
import os

from meshroom.core import desc
from meshroom.core.utils import COLORSPACES, VERBOSE_LEVEL


class PanoramaPostProcessing(desc.CommandLineNode):
    commandLine = 'aliceVision_panoramaPostProcessing {allParams}'
    cpu = desc.Level.NORMAL
    ram = desc.Level.INTENSIVE

    category = 'Panorama HDR'
    documentation = '''
Post process the panorama.
'''

    inputs = [
        desc.File(
            name="inputPanorama",
            label="Input Panorama",
            description="Input panorama image.",
            value="",
            uid=[0],
        ),
        desc.BoolParam(
            name="fillHoles",
            label="Fill Holes Algorithm",
            description="Fill the non attributed pixels with push pull algorithm if set.",
            value=False,
            uid=[0],
        ),
        desc.BoolParam(
            name="exportLevels",
            label="Export Downscaled Levels",
            description="Export downscaled panorama levels.",
            value=False,
            uid=[0],
        ),
        desc.IntParam(
            name="lastLevelMaxSize",
            label="Last Level Max Size",
            description="Maximum width of smallest downscaled panorama level.",
            value=3840,
            range=(1, 100000),
            uid=[0],
        ),
        desc.IntParam(
            name="previewSize",
            label="Panorama Preview Width",
            description="The width (in pixels) of the output panorama preview.",
            value=1000,
            range=(0, 5000, 100),
            uid=[0],
        ),
        desc.ChoiceParam(
            name="outputColorSpace",
            label="Output Color Space",
            description="The color space of the output image.",
            values=COLORSPACES,
            value="Linear",
            exclusive=True,
            uid=[0],
        ),
        desc.ChoiceParam(
            name="compressionMethod",
            label="Compression Method",
            description="Compression method for output EXR image.",
            value="auto",
            values=["none", "auto", "rle", "zip", "zips", "piz", "pxr24", "b44", "b44a", "dwaa", "dwab"],
            exclusive=True,
            uid=[0],
        ),
        desc.IntParam(
            name="compressionLevel",
            label="Compression Level",
            description="Level of compression for the output EXR image. The range depends on method used.\n"
                        "For zip/zips methods, values must be between 1 and 9.\n"
                        "A value of 0 will be ignored, default value for the selected method will be used.",
            value=0,
            range=(0, 500, 1),
            uid=[0],
            enabled=lambda node: node.compressionMethod.value in ["dwaa", "dwab", "zip", "zips"],
        ),
        desc.StringParam(
            name="panoramaName",
            label="Output Panorama Name",
            description="Name of the output panorama.",
            value="panorama.exr",
            uid=[],
            group=None,
            advanced=True,
        ),
        desc.StringParam(
            name="previewName",
            label="Panorama Preview Name",
            description="Name of the preview of the output panorama.",
            value="panoramaPreview.jpg",
            uid=[],
            group=None,
            advanced=True,
        ),
        desc.ChoiceParam(
            name="verboseLevel",
            label="Verbose Level",
            description="Verbosity level (fatal, error, warning, info, debug, trace).",
            values=VERBOSE_LEVEL,
            value="info",
            exclusive=True,
            uid=[],
        ),
    ]

    outputs = [
        desc.File(
            name="outputPanorama",
            label="Output Panorama",
            description="Generated panorama in EXR format.",
            semantic="image",
            value=lambda attr: desc.Node.internalFolder + attr.node.panoramaName.value,
            uid=[],
        ),
        desc.File(
            name="outputPanoramaPreview",
            label="Output Panorama Preview",
            description="Preview of the generated panorama in JPG format.",
            semantic="image",
            value=lambda attr: desc.Node.internalFolder + attr.node.previewName.value,
            uid=[],
        ),
        desc.File(
            name="downscaledPanoramaLevels",
            label="Downscaled Panorama Levels",
            description="Downscaled versions of the generated panorama.",
            value=lambda attr: desc.Node.internalFolder + os.path.splitext(attr.node.panoramaName.value)[0] + "_level_*.exr",
            uid=[],
            group="",
        ),
    ]
