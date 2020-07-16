# Multiview pipeline version
__version__ = "2.2"

import os

from meshroom.core.graph import Graph, GraphModification

# Supported image extensions
imageExtensions = ('.jpg', '.jpeg', '.tif', '.tiff', '.png', '.exr',
                   '.rw2', '.cr2', '.nef', '.arw',
                   '.dpx',
                   )
videoExtensions = ('.avi', '.mov', '.qt',
                   '.mkv', '.webm',
                   '.mp4', '.mpg', '.mpeg', '.m2v', '.m4v',
                   '.wmv',
                   '.ogv', '.ogg',
                   '.mxf')
panoramaInfoExtensions = ('.xml')


def hasExtension(filepath, extensions):
    """ Return whether filepath is one of the following extensions. """
    return os.path.splitext(filepath)[1].lower() in extensions


class FilesByType:
    def __init__(self):
        self.images = []
        self.videos = []
        self.panoramaInfo = []
        self.other = []

    def __bool__(self):
        return self.images or self.videos or self.panoramaInfo

    def extend(self, other):
        self.images.extend(other.images)
        self.videos.extend(other.videos)
        self.panoramaInfo.extend(other.panoramaInfo)
        self.other.extend(other.other)

    def addFile(self, file):
        if hasExtension(file, imageExtensions):
            self.images.append(file)
        elif hasExtension(file, videoExtensions):
            self.videos.append(file)
        elif hasExtension(file, panoramaInfoExtensions):
            self.panoramaInfo.append(file)
        else:
            self.other.append(file)

    def addFiles(self, files):
        for file in files:
            self.addFile(file)


def findFilesByTypeInFolder(folder, recursive=False):
    """
    Return all files that are images in 'folder' based on their extensions.

    Args:
        folder (str): folder to look into or list of folder/files

    Returns:
        list: the list of image files with a supported extension.
    """
    inputFolders = []
    if isinstance(folder, (list, tuple)):
        inputFolders = folder
    else:
        inputFolders.append(folder)

    output = FilesByType()
    for currentFolder in inputFolders:
        if os.path.isfile(currentFolder):
            output.addFile(currentFolder)
            continue
        elif os.path.isdir(currentFolder):
            if recursive:
                for root, directories, files in os.walk(currentFolder):
                    for filename in files:
                        output.addFile(os.path.join(root, filename))
            else:
                output.addFiles([os.path.join(currentFolder, filename) for filename in os.listdir(currentFolder)])
        else:
            # if not a diretory or a file, it may be an expression
            import glob
            paths = glob.glob(currentFolder)
            filesByType = findFilesByTypeInFolder(paths, recursive=recursive)
            output.extend(filesByType)

    return output


def hdri(inputImages=None, inputViewpoints=None, inputIntrinsics=None, output='', graph=None):
    """
    Create a new Graph with a complete HDRI pipeline.

    Args:
        inputImages (list of str, optional): list of image file paths
        inputViewpoints (list of Viewpoint, optional): list of Viewpoints
        output (str, optional): the path to export reconstructed model to

    Returns:
        Graph: the created graph
    """
    if not graph:
        graph = Graph('HDRI')
    with GraphModification(graph):
        nodes = hdriPipeline(graph)
        cameraInit = nodes[0]
        if inputImages:
            cameraInit.viewpoints.extend([{'path': image} for image in inputImages])
        if inputViewpoints:
            cameraInit.viewpoints.extend(inputViewpoints)
        if inputIntrinsics:
            cameraInit.intrinsics.extend(inputIntrinsics)

        if output:
            imageProcessing = nodes[-1]
            graph.addNewNode('Publish', output=output, inputFiles=[imageProcessing.outputImages])

    return graph

def hdriFisheye(inputImages=None, inputViewpoints=None, inputIntrinsics=None, output='', graph=None):
    if not graph:
        graph = Graph('HDRI-Fisheye')
    with GraphModification(graph):
        hdri(inputImages, inputViewpoints, inputIntrinsics, output, graph)
        for panoramaInit in graph.nodesByType("PanoramaInit"):
            panoramaInit.attribute("useFisheye").value = True
    return graph

def hdriPipeline(graph):
    """
    Instantiate an HDRI pipeline inside 'graph'.
    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated

    Returns:
        list of Node: the created nodes
    """
    cameraInit = graph.addNewNode('CameraInit')
    try:
        # fisheye4 does not work well in the ParoramaEstimation, so here we avoid to use it.
        cameraInit.attribute('allowedCameraModels').value.remove("fisheye4")
    except ValueError:
        pass

    panoramaPrepareImages = graph.addNewNode('PanoramaPrepareImages',
                               input=cameraInit.output)

    ldr2hdrSampling = graph.addNewNode('LdrToHdrSampling',
                               input=panoramaPrepareImages.output)

    ldr2hdrCalibration = graph.addNewNode('LdrToHdrCalibration',
                               input=ldr2hdrSampling.input,
                               samples=ldr2hdrSampling.output)

    ldr2hdrMerge = graph.addNewNode('LdrToHdrMerge',
                               input=ldr2hdrCalibration.input,
                               response=ldr2hdrCalibration.response)

    featureExtraction = graph.addNewNode('FeatureExtraction',
                                         input=ldr2hdrMerge.outSfMData,
                                         describerPreset='high')

    panoramaInit = graph.addNewNode('PanoramaInit',
                                     input=featureExtraction.input,
                                     dependency=[featureExtraction.output]  # Workaround for tractor submission with a fake dependency
                                     )

    imageMatching = graph.addNewNode('ImageMatching',
                                     input=panoramaInit.outSfMData,
                                     featuresFolders=[featureExtraction.output],
                                     method='FrustumOrVocabularyTree')

    featureMatching = graph.addNewNode('FeatureMatching',
                                       input=imageMatching.input,
                                       featuresFolders=imageMatching.featuresFolders,
                                       imagePairsList=imageMatching.output)

    panoramaEstimation = graph.addNewNode('PanoramaEstimation',
                                           input=featureMatching.input,
                                           featuresFolders=featureMatching.featuresFolders,
                                           matchesFolders=[featureMatching.output])

    panoramaOrientation = graph.addNewNode('SfMTransform',
                                           input=panoramaEstimation.output,
                                           method='from_single_camera')

    panoramaWarping = graph.addNewNode('PanoramaWarping',
                                       input=panoramaOrientation.output)

    panoramaCompositing = graph.addNewNode('PanoramaCompositing',
                                           input=panoramaWarping.input,
                                           warpingFolder=panoramaWarping.output)

    imageProcessing = graph.addNewNode('ImageProcessing',
                                       input=panoramaCompositing.output,
                                       fillHoles=True,
                                       extension='exr')

    return [
        cameraInit,
        featureExtraction,
        panoramaInit,
        imageMatching,
        featureMatching,
        panoramaEstimation,
        panoramaOrientation,
        panoramaWarping,
        panoramaCompositing,
        imageProcessing,
    ]



def photogrammetry(inputImages=list(), inputViewpoints=list(), inputIntrinsics=list(), output='', graph=None):
    """
    Create a new Graph with a complete photogrammetry pipeline.

    Args:
        inputImages (list of str, optional): list of image file paths
        inputViewpoints (list of Viewpoint, optional): list of Viewpoints
        output (str, optional): the path to export reconstructed model to

    Returns:
        Graph: the created graph
    """
    if not graph:
        graph = Graph('Photogrammetry')
    with GraphModification(graph):
        sfmNodes, mvsNodes = photogrammetryPipeline(graph)
        cameraInit = sfmNodes[0]
        cameraInit.viewpoints.extend([{'path': image} for image in inputImages])
        cameraInit.viewpoints.extend(inputViewpoints)
        cameraInit.intrinsics.extend(inputIntrinsics)

        if output:
            texturing = mvsNodes[-1]
            graph.addNewNode('Publish', output=output, inputFiles=[texturing.outputMesh,
                                                                   texturing.outputMaterial,
                                                                   texturing.outputTextures])

    return graph


def photogrammetryPipeline(graph):
    """
    Instantiate a complete photogrammetry pipeline inside 'graph'.

    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated

    Returns:
        list of Node: the created nodes
    """
    sfmNodes = sfmPipeline(graph)
    mvsNodes = mvsPipeline(graph, sfmNodes[-1])

    # store current pipeline version in graph header
    graph.header.update({'pipelineVersion': __version__})

    return sfmNodes, mvsNodes


def sfmPipeline(graph):
    """
    Instantiate a SfM pipeline inside 'graph'.
    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated

    Returns:
        list of Node: the created nodes
    """
    cameraInit = graph.addNewNode('CameraInit')

    featureExtraction = graph.addNewNode('FeatureExtraction',
                                         input=cameraInit.output)
    imageMatching = graph.addNewNode('ImageMatching',
                                     input=featureExtraction.input,
                                     featuresFolders=[featureExtraction.output])
    featureMatching = graph.addNewNode('FeatureMatching',
                                       input=imageMatching.input,
                                       featuresFolders=imageMatching.featuresFolders,
                                       imagePairsList=imageMatching.output)
    structureFromMotion = graph.addNewNode('StructureFromMotion',
                                           input=featureMatching.input,
                                           featuresFolders=featureMatching.featuresFolders,
                                           matchesFolders=[featureMatching.output])
    return [
        cameraInit,
        featureExtraction,
        imageMatching,
        featureMatching,
        structureFromMotion
    ]


def mvsPipeline(graph, sfm=None):
    """
    Instantiate a MVS pipeline inside 'graph'.

    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated
        sfm (Node, optional): if specified, connect the MVS pipeline to this StructureFromMotion node

    Returns:
        list of Node: the created nodes
    """
    if sfm and not sfm.nodeType == "StructureFromMotion":
        raise ValueError("Invalid node type. Expected StructureFromMotion, got {}.".format(sfm.nodeType))

    prepareDenseScene = graph.addNewNode('PrepareDenseScene',
                                         input=sfm.output if sfm else "")
    depthMap = graph.addNewNode('DepthMap',
                                input=prepareDenseScene.input,
                                imagesFolder=prepareDenseScene.output)
    depthMapFilter = graph.addNewNode('DepthMapFilter',
                                      input=depthMap.input,
                                      depthMapsFolder=depthMap.output)
    meshing = graph.addNewNode('Meshing',
                               input=depthMapFilter.input,
                               depthMapsFolder=depthMapFilter.output)
    meshFiltering = graph.addNewNode('MeshFiltering',
                                     inputMesh=meshing.outputMesh)
    texturing = graph.addNewNode('Texturing',
                                 input=meshing.output,
                                 imagesFolder=depthMap.imagesFolder,
                                 inputMesh=meshFiltering.outputMesh)

    return [
        prepareDenseScene,
        depthMap,
        depthMapFilter,
        meshing,
        meshFiltering,
        texturing
    ]


def sfmAugmentation(graph, sourceSfm, withMVS=False):
    """
    Create a SfM augmentation inside 'graph'.

    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated
        sourceSfm (Node, optional): if specified, connect the MVS pipeline to this StructureFromMotion node
        withMVS (bool): whether to create a MVS pipeline after the augmented SfM branch

    Returns:
        tuple: the created nodes (sfmNodes, mvsNodes)
    """
    cameraInit = graph.addNewNode('CameraInit')

    featureExtraction = graph.addNewNode('FeatureExtraction',
                                         input=cameraInit.output)
    imageMatchingMulti = graph.addNewNode('ImageMatchingMultiSfM',
                                          input=featureExtraction.input,
                                          featuresFolders=[featureExtraction.output]
                                          )
    featureMatching = graph.addNewNode('FeatureMatching',
                                       input=imageMatchingMulti.outputCombinedSfM,
                                       featuresFolders=imageMatchingMulti.featuresFolders,
                                       imagePairsList=imageMatchingMulti.output)
    structureFromMotion = graph.addNewNode('StructureFromMotion',
                                           input=featureMatching.input,
                                           featuresFolders=featureMatching.featuresFolders,
                                           matchesFolders=[featureMatching.output])
    graph.addEdge(sourceSfm.output, imageMatchingMulti.inputB)

    sfmNodes = [
        cameraInit,
        featureMatching,
        imageMatchingMulti,
        featureMatching,
        structureFromMotion
    ]

    mvsNodes = []

    if withMVS:
        mvsNodes = mvsPipeline(graph, structureFromMotion)

    return sfmNodes, mvsNodes
