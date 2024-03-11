__version__ = "1.0"

from meshroom.core import desc
from meshroom.core.utils import DESCRIBER_TYPES, VERBOSE_LEVEL

class RelativePoseEstimating(desc.AVCommandLineNode):
    commandLine = 'aliceVision_relativePoseEstimating {allParams}'
    size = desc.DynamicNodeSize('input')
    
    parallelization = desc.Parallelization(blockSize=25)
    commandLineRange = '--rangeStart {rangeStart} --rangeSize {rangeBlockSize}'

    category = 'Sparse Reconstruction'
    documentation = '''
Estimate relative pose between each pair of views that share tracks.
'''

    inputs = [
        desc.File(
            name="input",
            label="SfMData",
            description="SfMData file.",
            value="",
            uid=[0],
        ),
        desc.ListAttribute(
            elementDesc=desc.File(
                name="featuresFolder",
                label="Features Folder",
                description="",
                value="",
                uid=[0],
            ),
            name="featuresFolders",
            label="Features Folders",
            description="Folder(s) containing the extracted features and descriptors.",
        ),
        desc.File(
            name="tracksFilename",
            label="Tracks File",
            description="Tracks file.",
            value="",
            uid=[0],
        ),
        desc.ChoiceParam(
            name="describerTypes",
            label="Describer Types",
            description="Describer types used to describe an image.",
            values=DESCRIBER_TYPES,
            value=["dspsift"],
            exclusive=False,
            uid=[0],
            joinChar=",",
        ),
        desc.BoolParam(
            name="enforcePureRotation",
            label="Enforce pure rotation",
            description="Enforce pure rotation as a model",
            value=False,
            uid=[0],
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
            name="output",
            label="Pairs Info",
            description="Path to the output Pairs info files directory.",
            value=desc.Node.internalFolder,
            uid=[],
        ),
    ]
