import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.11
import MaterialIcons 2.2
import Controls 1.0
import Utils 1.0

FocusScope {
    id: root

    clip: true

    property var displayedNode: null

    property bool useExternal: false
    property url sourceExternal

    property url source
    property var viewIn3D

    property Component floatViewerComp: Qt.createComponent("FloatImage.qml")
    property Component panoramaViewerComp: Qt.createComponent("PanoramaViewer.qml")
    property var useFloatImageViewer: displayHDR.checked
    property alias useLensDistortionViewer: displayLensDistortionViewer.checked
    property alias usePanoramaViewer: displayPanoramaViewer.checked

    property var activeNodeFisheye: _reconstruction ? _reconstruction.activeNodes.get("PanoramaInit").node : null
    property bool cropFisheye : activeNodeFisheye ? activeNodeFisheye.attribute("useFisheye").value : false
    property bool enable8bitViewer: enable8bitViewerAction.checked
    property bool enableSequencePlayer: enableSequencePlayerAction.checked

    readonly property alias sync3DSelected: sequencePlayer.sync3DSelected

    QtObject {
        id: m
        property variant viewpointMetadata: {
            // Metadata from viewpoint attribute
            // Read from the reconstruction object
            if (_reconstruction) {
                let vp = getViewpoint(_reconstruction.selectedViewId)
                if (vp) {
                    return JSON.parse(vp.childAttribute("metadata").value)
                }
            }
            return {}
        }
        property variant imgMetadata: {
            // Metadata from FloatImage viewer
            // Directly read from the image file on disk
            if (floatImageViewerLoader.active) {
                return floatImageViewerLoader.item.metadata
            }
            // Use viewpoint metadata for the special case of the 8-bit viewer
            if (qtImageViewerLoader.active) {
                return viewpointMetadata
            }
            return {}
        }
    }

    Loader {
        id: aliceVisionPluginLoader
        active: true
        source: "TestAliceVisionPlugin.qml"
    }

    readonly property bool aliceVisionPluginAvailable: aliceVisionPluginLoader.status === Component.Ready

    Component.onCompleted: {
        if (!aliceVisionPluginAvailable) {
            console.warn("Missing plugin qtAliceVision.")
            displayHDR.checked = false
        }
    }

    property string loadingModules: {
        if (!imgContainer.image)
            return ""
        var res = ""
        if (imgContainer.image.imageStatus === Image.Loading) {
            res += " Image"
        }
        if (mfeaturesLoader.status === Loader.Ready) {
            if (mfeaturesLoader.item && mfeaturesLoader.item.status === MFeatures.Loading)
                res += " Features"
        }
        if (mtracksLoader.status === Loader.Ready) {
            if (mtracksLoader.item && mtracksLoader.item.status === MTracks.Loading)
                res += " Tracks"
        }
        if (msfmDataLoader.status === Loader.Ready) {
            if (msfmDataLoader.item && msfmDataLoader.item.status === MSfMData.Loading)
                res += " SfMData"
        }
        return res
    }

    function clear() {
        source = ''
    }

    // slots
    Keys.onPressed: {
        if (event.key === Qt.Key_F) {
            root.fit()
            event.accepted = true
        }
    }

    // mouse area
    MouseArea {
        anchors.fill: parent
        property double factor: 1.2
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: {
            imgContainer.forceActiveFocus()
            if (mouse.button & Qt.MiddleButton || (mouse.button & Qt.LeftButton && mouse.modifiers & Qt.ShiftModifier))
                drag.target = imgContainer // start drag
        }
        onReleased: {
            drag.target = undefined // stop drag
            if (mouse.button & Qt.RightButton) {
                var menu = contextMenu.createObject(root)
                menu.x = mouse.x
                menu.y = mouse.y
                menu.open()
            }
        }
        onWheel: {
            var zoomFactor = wheel.angleDelta.y > 0 ? factor : 1 / factor

            if (Math.min(imgContainer.width, imgContainer.image.height) * imgContainer.scale * zoomFactor < 10)
                return
            var point = mapToItem(imgContainer, wheel.x, wheel.y)
            imgContainer.x += (1-zoomFactor) * point.x * imgContainer.scale
            imgContainer.y += (1-zoomFactor) * point.y * imgContainer.scale
            imgContainer.scale *= zoomFactor
        }
    }

    onEnable8bitViewerChanged: {
        if (!enable8bitViewer) {
            displayHDR.checked = true
        }
    }

    // functions
    function fit() {
        // make sure the image is ready for use
        if (!imgContainer.image)
            return

        // for Exif orientation tags 5 to 8, a 90 degrees rotation is applied
        // therefore image dimensions must be inverted
        let dimensionsInverted = ["5", "6", "7", "8"].includes(imgContainer.orientationTag)
        let orientedWidth = dimensionsInverted ? imgContainer.image.height : imgContainer.image.width
        let orientedHeight = dimensionsInverted ? imgContainer.image.width : imgContainer.image.height

        // fit oriented image
        imgContainer.scale = Math.min(imgLayout.width / orientedWidth, root.height / orientedHeight)
        imgContainer.x = Math.max((imgLayout.width - orientedWidth * imgContainer.scale) * 0.5, 0)
        imgContainer.y = Math.max((imgLayout.height - orientedHeight * imgContainer.scale) * 0.5, 0)

        // correct position when image dimensions are inverted
        // so that container center corresponds to image center
        imgContainer.x += (orientedWidth - imgContainer.image.width) * 0.5 * imgContainer.scale
        imgContainer.y += (orientedHeight - imgContainer.image.height) * 0.5 * imgContainer.scale
    }

    function tryLoadNode(node) {
        useExternal = false

        // safety check
        if (!node) {
            return false
        }

        // node must be computed or at least running
        if (node.isComputable && !node.isPartiallyFinished()) {
            return false
        }

        // node must have at least one output attribute with the image semantic
        if (!node.hasImageOutput) {
            return false
        }

        displayedNode = node
        return true
    }

    function loadExternal(path) {
        useExternal = true
        sourceExternal = path
        displayedNode = null
    }

    function getViewpoint(viewId) {
        // Get viewpoint from cameraInit with matching id
        // This requires to loop over all viewpoints

        for (var i = 0; i < _reconstruction.viewpoints.count; i++) {
            var vp = _reconstruction.viewpoints.at(i)
            if (vp.childAttribute("viewId").value == viewId) {
                return vp
            }
        }

        return undefined
    }

    function getAttributeByName(node, attrName) {
        // Get attribute from given node by name
        // This requires to loop over all atributes

        for (var i = 0; i < node.attributes.count; i++) {
            var attr = node.attributes.at(i)
            if (attr.name == attrName) {
                return attr
            }
        }

        return undefined
    }


    function getImageFile() {
        // Entry point for getting the image file URL

        if (useExternal) {
            return sourceExternal
        }

        if (_reconstruction && (!displayedNode || outputAttribute.name == "gallery")) {
            let vp = getViewpoint(_reconstruction.pickedViewId)
            let path = vp ? vp.childAttribute("path").value : ""
            return Filepath.stringToUrl(path)
        }

        if (_reconstruction) {
            let vp = getViewpoint(_reconstruction.pickedViewId)
            let attr = getAttributeByName(displayedNode, outputAttribute.name)
            let path = attr ? attr.value : ""
            let resolved = vp ? Filepath.resolve(path, vp) : path
            return Filepath.stringToUrl(resolved)
        }

        return undefined
    }

    function buildOrderedSequence(path_template) {
        // Resolve the path template on the sequence of viewpoints
        // ordered by path

        let objs = []
        for (let i = 0; i < _reconstruction.viewpoints.count; i++) {
            objs.push(_reconstruction.viewpoints.at(i))
        }
        objs.sort((a, b) => { return a.childAttribute("path").value < b.childAttribute("path").value ? -1 : 1; })

        let seq = [];
        for (let i = 0; i < objs.length; i++) {
            seq.push(Filepath.resolve(path_template, objs[i]))
        }

        return seq
    }

    function getSequence() {
        // Entry point for getting the current image sequence

        if (useExternal) {
            return []
        }

        if (_reconstruction && (!displayedNode || outputAttribute.name == "gallery")) {
            return buildOrderedSequence("<PATH>")
        }

        if (_reconstruction) {
            let attr = getAttributeByName(displayedNode, outputAttribute.name)
            let path_template = attr ? attr.value : ""
            return buildOrderedSequence(path_template)
        }

        return []
    }

    onDisplayedNodeChanged: {
        if (!displayedNode) {
            root.source = ""
        }

        // update output attribute names
        var names = []
        if (displayedNode) {
            // store attr name for output attributes that represent images
            for (var i = 0; i < displayedNode.attributes.count; i++) {
                var attr = displayedNode.attributes.at(i)
                if (attr.isOutput && attr.desc.semantic === "image" && attr.enabled) {
                    names.push(attr.name)
                }
            }
        }
        if (!displayedNode || displayedNode.isComputable) names.push("gallery")
        outputAttribute.names = names

        root.source = getImageFile()
    }

    Connections {
        target: _reconstruction
        function onSelectedViewIdChanged() {
            root.source = getImageFile()
            if (useExternal)
                useExternal = false
        }
    }

    Connections {
        target: displayedNode
        function onOutputAttrEnabledChanged() {
            tryLoadNode(displayedNode)
        }
    }

    // context menu
    property Component contextMenu: Menu {
        MenuItem {
            text: "Fit"
            onTriggered: fit()
        }
        MenuItem {
            text: "Zoom 100%"
            onTriggered: {
                imgContainer.scale = 1
                imgContainer.x = Math.max((imgLayout.width - imgContainer.width * imgContainer.scale) * 0.5, 0)
                imgContainer.y = Math.max((imgLayout.height - imgContainer.height * imgContainer.scale) * 0.5, 0)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent

        HdrImageToolbar {
            id: hdrImageToolbar
            anchors.margins: 0
            visible: displayImageToolBarAction.checked && displayImageToolBarAction.enabled
            Layout.fillWidth: true
            onVisibleChanged: {
                resetDefaultValues()
            }
            colorPickerVisible: {
                return !displayPanoramaViewer.checked
            }

            colorRGBA: {
                if (!floatImageViewerLoader.item ||
                    floatImageViewerLoader.item.imageStatus !== Image.Ready) {
                    return null
                }
                if (floatImageViewerLoader.item.containsMouse === false) {
                    return null
                }
                var pix = floatImageViewerLoader.item.pixelValueAt(Math.floor(floatImageViewerLoader.item.mouseX), Math.floor(floatImageViewerLoader.item.mouseY))
                return pix
            }
        }

        LensDistortionToolbar {
            id: lensDistortionImageToolbar
            anchors.margins: 0
            visible: displayLensDistortionToolBarAction.checked && displayLensDistortionToolBarAction.enabled
            Layout.fillWidth: true
        }

        PanoramaToolbar {
            id: panoramaViewerToolbar
            anchors.margins: 0
            visible: displayPanoramaToolBarAction.checked && displayPanoramaToolBarAction.enabled
            Layout.fillWidth: true
        }

        // Image
        Item {
            id: imgLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            Image {
                id: alphaBackground
                anchors.fill: parent
                visible: displayAlphaBackground.checked
                fillMode: Image.Tile
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignTop
                source: "../../img/checkerboard_light.png"
                scale: 4
                smooth: false
            }

            Item {
                id: imgContainer
                transformOrigin: Item.TopLeft
                property var orientationTag: m.imgMetadata ? m.imgMetadata["Orientation"] : 0

                // qtAliceVision Image Viewer
                ExifOrientedViewer {
                    id: floatImageViewerLoader
                    active: root.aliceVisionPluginAvailable && (root.useFloatImageViewer || root.useLensDistortionViewer) && !panoramaViewerLoader.active
                    visible: (floatImageViewerLoader.status === Loader.Ready) && active
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    property bool fittedOnce: false
                    property int previousWidth: 0
                    property int previousHeight: 0
                    property real targetSize: Math.max(width, height) * imgContainer.scale
                    onHeightChanged: {
                        /* Image size is not updated through a single signal with the floatImage viewer, unlike
                         * the simple QML image viewer: instead of updating straight away the width and height to x and
                         * y, the emitted signals look like:
                         * - width = -1, height = -1
                         * - width = x, height = -1
                         * - width = x, height = y
                         * We want to do the auto-fit on the first display of an image from the group, and then keep its
                         * scale when displaying another image from the group, so we need to know if an image in the
                         * group has already been auto-fitted. If we change the group of images (when another project is
                         * opened, for example, and the images have a different size), then another auto-fit needs to be
                         * performed */
                        if ((!fittedOnce && imgContainer.image && imgContainer.image.height > 0) ||
                            (fittedOnce && ((width > 1 && previousWidth != width) || (height > 1 && previousHeight != height)))) {
                            fit()
                            fittedOnce = true
                            previousWidth = width
                            previousHeight = height
                        }
                    }

                    onActiveChanged: {
                        if (active) {
                            // Instantiate and initialize a FLoatImage component dynamically using Loader.setSource
                            // Note: It does not work to use previously created component, so we re-create it with setSource.
                            setSource("FloatImage.qml", {
                                'source':  Qt.binding(function() { return getImageFile() }),
                                'gamma': Qt.binding(function() { return hdrImageToolbar.gammaValue }),
                                'gain': Qt.binding(function() { return hdrImageToolbar.gainValue }),
                                'channelModeString': Qt.binding(function() { return hdrImageToolbar.channelModeValue }),
                                'isPrincipalPointsDisplayed': Qt.binding(function() { return lensDistortionImageToolbar.displayPrincipalPoint }),
                                'surface.displayGrid':  Qt.binding(function() { return lensDistortionImageToolbar.visible && lensDistortionImageToolbar.displayGrid }),
                                'surface.gridOpacity': Qt.binding(function() { return lensDistortionImageToolbar.opacityValue }),
                                'surface.gridColor': Qt.binding(function() { return lensDistortionImageToolbar.color }),
                                'surface.subdivisions': Qt.binding(function() { return root.useFloatImageViewer ? 1 : lensDistortionImageToolbar.subdivisionsValue }),
                                'viewerTypeString': Qt.binding(function() { return displayLensDistortionViewer.checked ? "distortion" : "hdr" }),
                                'sfmRequired': Qt.binding(function() { return displayLensDistortionViewer.checked ? true : false }),
                                'surface.msfmData': Qt.binding(function() { return (msfmDataLoader.status === Loader.Ready && msfmDataLoader.item != null && msfmDataLoader.item.status === 2) ? msfmDataLoader.item : null }),
                                'canBeHovered': false,
                                'idView': Qt.binding(function() { return (_reconstruction ? _reconstruction.selectedViewId : -1) }),
                                'cropFisheye': false,
                                'sequence': Qt.binding(function() { return ((root.enableSequencePlayer && _reconstruction && _reconstruction.viewpoints.count > 0) ? getSequence() : []) }),
                                'targetSize': Qt.binding(function() { return floatImageViewerLoader.targetSize }),
                                'useSequence': Qt.binding(function() { return root.enableSequencePlayer && !useExternal && _reconstruction })
                                })
                          } else {
                                // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                                setSource("", {})
                                fittedOnce = false
                          }
                    }
                }

                // qtAliceVision Panorama Viewer
                Loader {
                    id: panoramaViewerLoader
                    active: root.aliceVisionPluginAvailable && root.usePanoramaViewer && _reconstruction.activeNodes.get('sfm').node
                    visible: (panoramaViewerLoader.status === Loader.Ready) && active
                    anchors.centerIn: parent

                    onActiveChanged: {
                        if (active) {
                            setSource("PanoramaViewer.qml", {
                                'subdivisionsPano': Qt.binding(function() { return panoramaViewerToolbar.subdivisionsValue }),
                                'cropFisheyePano': Qt.binding(function() { return root.cropFisheye }),
                                'downscale': Qt.binding(function() { return panoramaViewerToolbar.downscaleValue }),
                                'isEditable': Qt.binding(function() { return panoramaViewerToolbar.enableEdit }),
                                'isHighlightable': Qt.binding(function() { return panoramaViewerToolbar.enableHover }),
                                'displayGridPano': Qt.binding(function() { return panoramaViewerToolbar.displayGrid }),
                                'mouseMultiplier': Qt.binding(function() { return panoramaViewerToolbar.mouseSpeed }),
                                'msfmData': Qt.binding(function() { return (msfmDataLoader && msfmDataLoader.item && msfmDataLoader.status === Loader.Ready
                                                                           && msfmDataLoader.item.status === 2) ? msfmDataLoader.item : null }),
                            })
                        } else {
                            // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                            setSource("", {})
                            displayPanoramaViewer.checked = false
                        }
                    }
                }

                // Simple QML Image Viewer (using Qt or qtAliceVisionImageIO to load images)
                ExifOrientedViewer {
                    id: qtImageViewerLoader
                    active: !floatImageViewerLoader.active && !panoramaViewerLoader.active
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    sourceComponent: Image {
                        id: qtImageViewer
                        asynchronous: true
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                        onWidthChanged: if (status==Image.Ready) fit()
                        source: getImageFile()
                        onStatusChanged: {
                            // update cache source when image is loaded
                            if (status === Image.Ready)
                                qtImageViewerCache.source = source
                        }

                        // Image cache of the last loaded image
                        // Only visible when the main one is loading, to maintain a displayed image for smoother transitions
                        Image {
                            id: qtImageViewerCache

                            anchors.fill: parent
                            asynchronous: true
                            smooth: parent.smooth
                            fillMode: parent.fillMode

                            visible: qtImageViewer.status === Image.Loading
                        }
                    }
                }

                property var image: {
                    if (floatImageViewerLoader.active)
                        floatImageViewerLoader.item
                    else if (panoramaViewerLoader.active)
                        panoramaViewerLoader.item
                    else
                        qtImageViewerLoader.item
                }
                width: image ? (image.width > 0 ? image.width : 1) : 1
                height: image ? (image.height > 0 ? image.height : 1) : 1
                scale: 1.0

                // FeatureViewer: display view extracted feature points
                // note: requires QtAliceVision plugin - use a Loader to evaluate plugin availability at runtime
                ExifOrientedViewer {
                    id: featuresViewerLoader
                    active: displayFeatures.checked && !useExternal
                    property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("featureProvider").node : null
                    width: imgContainer.width
                    height: imgContainer.height
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2

                    onActiveChanged: {
                        if (active) {
                            // Instantiate and initialize a FeaturesViewer component dynamically using Loader.setSource
                            setSource("FeaturesViewer.qml", {
                                'model': Qt.binding(function() { return activeNode ? activeNode.attribute("describerTypes").value : "" }),
                                'currentViewId': Qt.binding(function() { return _reconstruction.selectedViewId }),
                                'features': Qt.binding(function() { return mfeaturesLoader.status === Loader.Ready ? mfeaturesLoader.item : null }),
                                'tracks': Qt.binding(function() { return mtracksLoader.status === Loader.Ready ? mtracksLoader.item : null }),
                                'sfmData': Qt.binding(function() { return msfmDataLoader.status === Loader.Ready ? msfmDataLoader.item : null }),
                                'sync3DSelected': Qt.binding(function() { return sequencePlayer.sync3DSelected }),
                            })
                        } else {
                            // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                            setSource("", {})
                        }
                    }
                }

                // FisheyeCircleViewer: display fisheye circle
                // Note: use a Loader to evaluate if a PanoramaInit node exist and displayFisheyeCircle checked at runtime
                ExifOrientedViewer {
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("PanoramaInit").node : null
                    active: displayFisheyeCircleLoader.checked && activeNode

                    sourceComponent: CircleGizmo {
                        width: imgContainer.width
                        height: imgContainer.height

                        property bool useAuto: activeNode.attribute("estimateFisheyeCircle").value
                        readOnly: useAuto
                        visible: (!useAuto) || activeNode.isComputed
                        property real userFisheyeRadius: activeNode.attribute("fisheyeRadius").value
                        property variant fisheyeAutoParams: _reconstruction.getAutoFisheyeCircle(activeNode)

                        circleX: useAuto ? fisheyeAutoParams.x : activeNode.attribute("fisheyeCenterOffset.fisheyeCenterOffset_x").value
                        circleY: useAuto ? fisheyeAutoParams.y : activeNode.attribute("fisheyeCenterOffset.fisheyeCenterOffset_y").value

                        circleRadius: useAuto ? fisheyeAutoParams.z : ((imgContainer.image ? Math.min(imgContainer.image.width, imgContainer.image.height) : 1.0) * 0.5 * (userFisheyeRadius * 0.01))

                        circleBorder.width: Math.max(1, (3.0 / imgContainer.scale))
                        onMoved: {
                            if (!useAuto) {
                                _reconstruction.setAttribute(
                                    activeNode.attribute("fisheyeCenterOffset"),
                                    JSON.stringify([xoffset, yoffset])
                                )
                            }
                        }
                        onIncrementRadius: {
                            if (!useAuto) {
                                _reconstruction.setAttribute(activeNode.attribute("fisheyeRadius"), activeNode.attribute("fisheyeRadius").value + radiusOffset)
                            }
                        }
                    }
                }

                // LightingCalibration: display circle
                ExifOrientedViewer {
                    property var activeNode: _reconstruction.activeNodes.get("SphereDetection").node 
    
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    active: displayLightingCircleLoader.checked && activeNode

                    sourceComponent: CircleGizmo {
                        property var jsonFolder: activeNode.attribute("output").value
                        property var json: null
                        property var currentViewId: _reconstruction.selectedViewId
                        property var nodeCircleX: activeNode.attribute("sphereCenter.x").value
                        property var nodeCircleY: activeNode.attribute("sphereCenter.y").value
                        property var nodeCircleRadius: activeNode.attribute("sphereRadius").value
                        
                        width: imgContainer.width
                        height: imgContainer.height
                        readOnly: activeNode.attribute("autoDetect").value
                        circleX: nodeCircleX
                        circleY: nodeCircleY
                        circleRadius: nodeCircleRadius
                        circleBorder.width: Math.max(1, (3.0 / imgContainer.scale))

                        onJsonFolderChanged: {
                            json = null
                            if(activeNode.attribute("autoDetect").value) {
                                // auto detection enabled
                                var jsonPath = activeNode.attribute("output").value + "/detection.json"
                                Request.get(Filepath.stringToUrl(jsonPath), function(xhr) {
                                    if (xhr.readyState === XMLHttpRequest.DONE) {
                                        try {
                                            json = JSON.parse(xhr.responseText)
                                        } catch(exc) {
                                            console.warn("Failed to parse SphereDetection JSON file: " + jsonPath)
                                        }
                                    }
                                    updateGizmo()
                                })
                            }
                        }

                        onCurrentViewIdChanged: { updateGizmo() }
                        onNodeCircleXChanged : { updateGizmo() }
                        onNodeCircleYChanged : { updateGizmo() }
                        onNodeCircleRadiusChanged : { updateGizmo() }

                        function updateGizmo() {
                            if(activeNode.attribute("autoDetect").value) {
                                // update gizmo from auto detection json file
                                if(json) { 
                                    // json file found
                                    var data = json[currentViewId]
                                    if(data && data[0]) { 
                                        // current view id found
                                        circleX = data[0].x
                                        circleY= data[0].y
                                        circleRadius = data[0].r
                                        return
                                    }
                                }
                                // no auto detection data
                                circleX = -1
                                circleY= -1
                                circleRadius = 0
                            }
                            else {
                                // update gizmo from node manual parameters
                                circleX = nodeCircleX
                                circleY = nodeCircleY
                                circleRadius = nodeCircleRadius
                            }
                        }

                        onMoved: {
                            _reconstruction.setAttribute(activeNode.attribute("sphereCenter"), JSON.stringify([xoffset, yoffset]))
                        }

                        onIncrementRadius: {
                            _reconstruction.setAttribute(activeNode.attribute("sphereRadius"), activeNode.attribute("sphereRadius").value + radiusOffset)
                        }
                    }
                }

                // ColorCheckerViewer: display color checker detection results
                // note: use a Loader to evaluate if a ColorCheckerDetection node exist and displayColorChecker checked at runtime
                ExifOrientedViewer {
                    id: colorCheckerViewerLoader
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("ColorCheckerDetection").node : null
                    active: (displayColorCheckerViewerLoader.checked && activeNode)

                    sourceComponent: ColorCheckerViewer {
                        width: imgContainer.width
                        height: imgContainer.height

                        visible: activeNode.isComputed && json !== undefined && imgContainer.image.imageStatus === Image.Ready
                        source: Filepath.stringToUrl(activeNode.attribute("outputData").value)
                        viewpoint: _reconstruction.selectedViewpoint
                        zoom: imgContainer.scale

                        updatePane: function() {
                            colorCheckerPane.colors = getColors();
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                FloatingPane {
                    id: imagePathToolbar
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: childrenRect.height
                    visible: displayImagePathAction.checked

                    RowLayout {
                        width: parent.width
                        height: childrenRect.height

                        // selectable filepath to source image
                        TextField {
                            padding: 0
                            background: Item {}
                            horizontalAlignment: TextInput.AlignLeft
                            Layout.fillWidth: true
                            height: contentHeight
                            font.pointSize: 8
                            readOnly: true
                            selectByMouse: true
                            text: Filepath.urlToString(getImageFile())
                        }

                        // write which node is being displayed
                        Label {
                            id: displayedNodeName
                            text: root.displayedNode ? root.displayedNode.label : ""
                            font.pointSize: 8

                            horizontalAlignment: TextInput.AlignLeft
                            Layout.fillWidth: false
                            Layout.preferredWidth: contentWidth
                            height: contentHeight
                        }

                        // button to clear currently displayed file
                        MaterialToolButton {
                            id: clearViewerButton
                            text: MaterialIcons.close
                            ToolTip.text: root.useExternal ? "Close external file" : "Clear node"
                            enabled: root.displayedNode || root.useExternal
                            visible: root.displayedNode || root.useExternal
                            onClicked: {
                                if (root.displayedNode) root.displayedNode = null
                                if (root.useExternal) root.useExternal = false
                            }
                        }
                    }
                }

                FloatingPane {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: childrenRect.height
                    visible: floatImageViewerLoader.item !== null && floatImageViewerLoader.item.imageStatus === Image.Error
                    Layout.alignment: Qt.AlignHCenter

                    RowLayout {
                        anchors.fill: parent

                        Label {
                            font.pointSize: 8
                            text: {
                                if (floatImageViewerLoader.item !== null) {
                                    switch (floatImageViewerLoader.item.status) {
                                        case 2:  // AliceVision.FloatImageViewer.EStatus.OUTDATED_LOADING
                                            return "Outdated Loading"
                                        case 3:  // AliceVision.FloatImageViewer.EStatus.MISSING_FILE
                                            return "Missing File"
                                        case 4:  // AliceVision.FloatImageViewer.EStatus.ERROR
                                            return "Error"
                                        default:
                                            return ""
                                    }
                                }
                                return ""
                            }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                Item {
                    id: imgPlaceholder
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Image Metadata overlay Pane
                    ImageMetadataView {
                        width: 350
                        anchors {
                            top: parent.top
                            right: parent.right
                            bottom: parent.bottom
                        }

                        visible: metadataCB.checked
                        // only load metadata model if visible
                        metadata: {
                            if (visible) {
                                if (root.useExternal || outputAttribute.name != "gallery") {
                                    return m.imgMetadata
                                } else {
                                    return m.viewpointMetadata
                                }
                            }
                            return {}
                        }
                    }

                    ColorCheckerPane {
                        id: colorCheckerPane
                        width: 250
                        height: 170
                        anchors {
                            top: parent.top
                            right: parent.right
                        }
                        visible: displayColorCheckerViewerLoader.checked && colorCheckerPane.colors !== null
                    }

                    Loader {
                        id: mfeaturesLoader

                        property bool isUsed: displayFeatures.checked
                        property var activeNode: {
                            if (!root.aliceVisionPluginAvailable) {
                                return null
                            }
                            return _reconstruction ? _reconstruction.activeNodes.get("featureProvider").node : null
                        }
                        property bool isComputed: activeNode && activeNode.isComputed
                        active: isUsed && isComputed

                        onActiveChanged: {
                            if (active) {
                                // instantiate and initialize a MFeatures component dynamically using Loader.setSource
                                // so it can fail safely if the c++ plugin is not available
                                setSource("MFeatures.qml", {
                                    'describerTypes': Qt.binding(function() {
                                        return activeNode ? activeNode.attribute("describerTypes").value : {}
                                    }),
                                    'featureFolders': Qt.binding(function() {
                                        let result = []
                                        if (activeNode) {
                                            if (activeNode.nodeType == "FeatureExtraction" && isComputed) {
                                                result.push(activeNode.attribute("output").value)
                                            } else if (activeNode.hasAttribute("featuresFolders")) {
                                                for (let i = 0; i < activeNode.attribute("featuresFolders").value.count; i++) {
                                                    let attr = activeNode.attribute("featuresFolders").value.at(i)
                                                    result.push(attr.value)
                                                }
                                            }
                                        }
                                        return result
                                    }),
                                    'viewIds': Qt.binding(function() {
                                        if (_reconstruction) {
                                            let result = [];
                                            for (let i = 0; i < _reconstruction.viewpoints.count; i++) {
                                                let vp = _reconstruction.viewpoints.at(i)
                                                result.push(vp.childAttribute("viewId").value)
                                            }
                                            return result
                                        }
                                        return {}
                                    }),
                                })
                            } else {
                                // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                                setSource("", {})
                            }
                        }
                    }
                    Loader {
                        id: msfmDataLoader

                        property bool isUsed: displayFeatures.checked || displaySfmStatsView.checked || displaySfmDataGlobalStats.checked
                                              || displayPanoramaViewer.checked || displayLensDistortionViewer.checked
                        property var activeNode: {
                            if (!root.aliceVisionPluginAvailable) {
                                return null
                            }
                            var nodeType = "sfm"
                            if (displayLensDistortionViewer.checked) {
                                nodeType = "sfmData"
                            }
                            var sfmNode = _reconstruction ? _reconstruction.activeNodes.get(nodeType).node : null
                            if (sfmNode === null) {
                                return null
                            }
                            if (displayPanoramaViewer.checked) {
                                sfmNode = _reconstruction.activeNodes.get('SfMTransform').node
                                var previousNode = sfmNode.attribute("input").rootLinkParam.node
                                return previousNode
                            }
                            return sfmNode
                        }
                        property bool isComputed: activeNode && activeNode.isComputed
                        property string filepath: {
                            var sfmValue = ""
                            if (isComputed && activeNode.hasAttribute("output")) {
                                sfmValue = activeNode.attribute("output").value
                            }
                            return Filepath.stringToUrl(sfmValue)
                        }

                        active: isUsed && isComputed

                        onActiveChanged: {
                            if (active) {
                                // instantiate and initialize a SfmStatsView component dynamically using Loader.setSource
                                // so it can fail safely if the c++ plugin is not available
                                setSource("MSfMData.qml", {
                                    'sfmDataPath': Qt.binding(function() { return filepath }),
                                })
                            } else {
                                // Force the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                                setSource("", {})
                            }
                        }
                    }
                    Loader {
                        id: mtracksLoader

                        property bool isUsed: displayFeatures.checked || displaySfmStatsView.checked || displaySfmDataGlobalStats.checked || displayPanoramaViewer.checked
                        property var activeNode: {
                            if (!root.aliceVisionPluginAvailable) {
                                return null
                            }
                            return _reconstruction ? _reconstruction.activeNodes.get("matchProvider").node : null
                        }
                        property bool isComputed: activeNode && activeNode.isComputed

                        active: isUsed && isComputed

                        onActiveChanged: {
                            if (active) {
                                // instantiate and initialize a SfmStatsView component dynamically using Loader.setSource
                                // so it can fail safely if the c++ plugin is not available
                                setSource("MTracks.qml", {
                                    'matchingFolders': Qt.binding(function() {
                                        let result = []
                                        if (activeNode) {
                                            if (activeNode.nodeType == "FeatureMatching" && isComputed) {
                                                result.push(activeNode.attribute("output").value)
                                            } else if (activeNode.hasAttribute("matchesFolders")) {
                                                for (let i = 0; i < activeNode.attribute("matchesFolders").value.count; i++) {
                                                    let attr = activeNode.attribute("matchesFolders").value.at(i)
                                                    result.push(attr.value)
                                                }
                                            }
                                        }
                                        return result
                                    }),
                                })
                            } else {
                                // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                                setSource("", {})
                            }
                        }
                    }
                    Loader {
                        id: sfmStatsView
                        anchors.fill: parent
                        active: msfmDataLoader.status === Loader.Ready && displaySfmStatsView.checked

                        onActiveChanged: {
                            // Load and unload the component explicitly
                            // (necessary since Qt 5.14, Component.onCompleted cannot be used anymore to load the data once and for all)
                            if (active) {
                                setSource("SfmStatsView.qml", {
                                    "msfmData": Qt.binding(function() { return msfmDataLoader.item }),
                                    "viewId": Qt.binding(function() { return _reconstruction.selectedViewId }),
                                })
                            } else {
                                setSource("", {})
                            }
                        }
                    }
                    Loader {
                        id: sfmGlobalStats
                        anchors.fill: parent
                        active: msfmDataLoader.status === Loader.Ready && displaySfmDataGlobalStats.checked

                        onActiveChanged: {
                            // Load and unload the component explicitly
                            // (necessary since Qt 5.14, Component.onCompleted cannot be used anymore to load the data once and for all)
                            if (active) {
                                setSource("SfmGlobalStats.qml", {
                                    'msfmData': Qt.binding(function() { return msfmDataLoader.item }),
                                    'mTracks': Qt.binding(function() { return mtracksLoader.item }),

                                })
                            } else {
                                setSource("", {})
                            }
                        }
                    }
                    Loader {
                        id: featuresOverlay
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            margins: 2
                        }
                        active: root.aliceVisionPluginAvailable && displayFeatures.checked && featuresViewerLoader.status === Loader.Ready

                        sourceComponent: FeaturesInfoOverlay {
                            pluginStatus: featuresViewerLoader.status
                            featuresViewer: featuresViewerLoader.item
                            mfeatures: mfeaturesLoader.item
                            mtracks: mtracksLoader.item
                            msfmdata: msfmDataLoader.item
                        }
                    }

                    Loader {
                        id: ldrHdrCalibrationGraph
                        anchors.fill: parent

                        property var activeNode: _reconstruction ? _reconstruction.activeNodes.get('LdrToHdrCalibration').node : null
                        property var isEnabled: displayLdrHdrCalibrationGraph.checked && activeNode && activeNode.isComputed
                        active: isEnabled

                        property var path: activeNode && activeNode.hasAttribute("response") ? activeNode.attribute("response").value : ""
                        property var vp: _reconstruction ? getViewpoint(_reconstruction.selectedViewId) : null

                        sourceComponent: CameraResponseGraph {
                            responsePath: Filepath.resolve(path, vp)
                        }
                    }
                }
                FloatingPane {
                    id: bottomToolbar
                    padding: 4
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height

                    RowLayout {
                        anchors.fill: parent

                        // zoom label
                        MLabel {
                            text: ((imgContainer.image && (imgContainer.image.imageStatus === Image.Ready)) ? imgContainer.scale.toFixed(2) : "1.00") + "x"
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: {
                                    if (mouse.button & Qt.LeftButton) {
                                        fit()
                                    } else if (mouse.button & Qt.RightButton) {
                                        var menu = contextMenu.createObject(root)
                                        var point = mapToItem(root, mouse.x, mouse.y)
                                        menu.x = point.x
                                        menu.y = point.y
                                        menu.open()
                                    }
                                }
                            }
                            ToolTip.text: "Zoom"
                        }
                        MaterialToolButton {
                            id: displayAlphaBackground
                            ToolTip.text: "Alpha Background"
                            text: MaterialIcons.texture
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                        }
                        MaterialToolButton
                        {
                            id: displayHDR
                            ToolTip.text: "High-Dynamic-Range Image Viewer"
                            text: MaterialIcons.hdr_on
                            // larger font but smaller padding,
                            // so it is visually similar.
                            font.pointSize: 20
                            padding: 0
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: root.aliceVisionPluginAvailable
                            enabled: root.aliceVisionPluginAvailable
                            visible: root.enable8bitViewer
                            onCheckedChanged : {
                                if (displayLensDistortionViewer.checked && checked) {
                                    displayLensDistortionViewer.checked = false
                                }
                                root.useFloatImageViewer = !root.useFloatImageViewer
                            }
                        }
                        MaterialToolButton {
                            id: displayLensDistortionViewer

                            property int numberChanges: null
                            property bool previousChecked: null
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfmData').node : null
                            property bool isComputed: {
                                if (!activeNode)
                                    return false
                                if (activeNode.isComputed)
                                    return true
                                if (!activeNode.hasAttribute("input"))
                                    return false
                                var inputAttr = activeNode.attribute("input")
                                var inputAttrLink = inputAttr.rootLinkParam
                                if (!inputAttrLink)
                                    return false
                                return inputAttrLink.node.isComputed
                            }

                            ToolTip.text: "Lens Distortion Viewer" + (isComputed ? (": " + activeNode.label) : "")
                            text: MaterialIcons.panorama_horizontal
                            font.pointSize: 16
                            padding: 0
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode && isComputed
                            onCheckedChanged : {
                                if ((displayHDR.checked || displayPanoramaViewer.checked) && checked) {
                                    displayHDR.checked = false
                                    displayPanoramaViewer.checked = false
                                } else if (!checked) {
                                    displayHDR.checked = true
                                }
                            }

                            onActiveNodeChanged: {
                                numberChanges += 1
                            }

                            onEnabledChanged: {
                                if (!enabled) {
                                    previousChecked = checked
                                    checked = false
                                    numberChanges = 0
                                }

                                if (enabled && (numberChanges == 1) && previousChecked) {
                                    checked = true
                                }
                            }
                        }
                        MaterialToolButton {
                            id: displayPanoramaViewer
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('SfMTransform').node : null
                            property bool isComputed: {
                                if (!activeNode)
                                    return false
                                if (activeNode.attribute("method").value !== "manual")
                                    return false
                                var inputAttr = activeNode.attribute("input")
                                if (!inputAttr)
                                    return false
                                var inputAttrLink = inputAttr.rootLinkParam
                                if (!inputAttrLink)
                                    return false
                                return inputAttrLink.node.isComputed
                            }

                            ToolTip.text: activeNode ? "Panorama Viewer " + activeNode.label : "Panorama Viewer"
                            text: MaterialIcons.panorama_photosphere
                            font.pointSize: 16
                            padding: 0
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode && isComputed
                            onCheckedChanged : {
                                if (displayLensDistortionViewer.checked && checked) {
                                    displayLensDistortionViewer.checked = false
                                }
                                if (displayFisheyeCircleLoader.checked && checked) {
                                    displayFisheyeCircleLoader.checked = false
                                }
                            }
                            onEnabledChanged : {
                                if (!enabled) {
                                    checked = false
                                }
                            }
                        }
                        MaterialToolButton {
                            id: displayFeatures
                            ToolTip.text: "Display Features"
                            text: MaterialIcons.scatter_plot
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true && !useExternal
                            checked: false
                            enabled: root.aliceVisionPluginAvailable && !displayPanoramaViewer.checked && !useExternal
                            onEnabledChanged : {
                                if (useExternal) return
                                if (enabled == false) checked = false
                            }
                        }
                        MaterialToolButton {
                            id: displayFisheyeCircleLoader
                            property var activeNode: _reconstruction ? _reconstruction.activeNodes.get('PanoramaInit').node : null
                            ToolTip.text: "Display Fisheye Circle: " + (activeNode ? activeNode.label : "No Node")
                            text: MaterialIcons.vignette
                            // text: MaterialIcons.panorama_fish_eye
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode && activeNode.attribute("useFisheye").value && !displayPanoramaViewer.checked
                            visible: activeNode
                        }
                        MaterialToolButton {
                            id: displayLightingCircleLoader
                            property var activeNode: _reconstruction.activeNodes.get('SphereDetection').node
                            ToolTip.text: "Display Lighting Circle: " + (activeNode ? activeNode.label : "No Node")
                            text: MaterialIcons.location_searching
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode
                            visible: activeNode
                        }
                        MaterialToolButton {
                            id: displayColorCheckerViewerLoader
                            property var activeNode: _reconstruction ? _reconstruction.activeNodes.get('ColorCheckerDetection').node : null
                            ToolTip.text: "Display Color Checker: " + (activeNode ? activeNode.label : "No Node")
                            text: MaterialIcons.view_comfy //view_module grid_on gradient view_comfy border_all
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                            enabled: activeNode && activeNode.isComputed && _reconstruction.selectedViewId !== -1
                            checked: false
                            visible: activeNode
                            onEnabledChanged: {
                                if (enabled == false)
                                    checked = false
                            }
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmDataGlobalStats.checked = false
                                    displaySfmStatsView.checked = false
                                    metadataCB.checked = false
                                }
                            }
                        }

                        MaterialToolButton {
                            id: displayLdrHdrCalibrationGraph
                            property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("LdrToHdrCalibration").node : null
                            property bool isComputed: activeNode && activeNode.isComputed
                            ToolTip.text: "Display Camera Response Function: " + (activeNode ? activeNode.label : "No Node")
                            text: MaterialIcons.timeline
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode && activeNode.isComputed
                            visible: activeNode

                            onIsComputedChanged: {
                                if (!isComputed)
                                    checked = false
                            }
                        }

                        Label {
                            id: resolutionLabel
                            Layout.fillWidth: true
                            text: (imgContainer.image && imgContainer.image.sourceSize.width > 0) ? (imgContainer.image.sourceSize.width + "x" + imgContainer.image.sourceSize.height) : ""

                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ComboBox {
                            id: outputAttribute
                            clip: true
                            Layout.minimumWidth: 0
                            flat: true

                            property var names: ["gallery"]
                            property string name: names[currentIndex]

                            model: names.map(n => (n === "gallery") ? "Image Gallery" : displayedNode.attributes.get(n).label)
                            enabled: count > 1

                            FontMetrics {
                                id: fontMetrics
                            }
                            Layout.preferredWidth: model.reduce((acc, label) => Math.max(acc, fontMetrics.boundingRect(label).width), 0) + 3.0 * Qt.application.font.pixelSize

                            onNameChanged: {
                                root.source = getImageFile()
                            }
                        }

                        MaterialToolButton {
                            id: displayImageOutputIn3D
                            enabled: root.aliceVisionPluginAvailable && _reconstruction && displayedNode && Filepath.basename(root.source).includes("depthMap")
                            ToolTip.text: "View Depth Map in 3D"
                            text: MaterialIcons.input
                            font.pointSize: 11
                            Layout.minimumWidth: 0

                            onClicked: {
                                root.viewIn3D(
                                    root.source,
                                    displayedNode.name + ":" + outputAttribute.name + " " + String(_reconstruction.selectedViewId)
                                )
                            }
                        }

                        MaterialToolButton {
                            id: displaySfmStatsView
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfm').node : null
                            property bool isComputed: activeNode && activeNode.isComputed

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.assessment

                            ToolTip.text: "StructureFromMotion Statistics" + (isComputed ? (": " + activeNode.label) : "")
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            enabled: activeNode && activeNode.isComputed && _reconstruction.selectedViewId >= 0
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmDataGlobalStats.checked = false
                                    metadataCB.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }

                        MaterialToolButton {
                            id: displaySfmDataGlobalStats
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfm').node : null
                            property bool isComputed: activeNode && activeNode.isComputed

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.language

                            ToolTip.text: "StructureFromMotion Global Statistics" + (isComputed ? (": " + activeNode.label) : "")
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            enabled: activeNode && activeNode.isComputed
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmStatsView.checked = false
                                    metadataCB.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }
                        MaterialToolButton {
                            id: metadataCB

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.info_outline

                            ToolTip.text: "Image Metadata"
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmDataGlobalStats.checked = false
                                    displaySfmStatsView.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }
                    }
                }

                SequencePlayer {
                    id: sequencePlayer
                    anchors.margins: 0
                    Layout.fillWidth: true
                    sortedViewIds: (root.enableSequencePlayer && _reconstruction && _reconstruction.viewpoints.count > 0) ? buildOrderedSequence("<VIEW_ID>") : []
                    viewer: floatImageViewerLoader.status === Loader.Ready ? floatImageViewerLoader.item : null
                    visible: root.enableSequencePlayer
                    enabled: root.enableSequencePlayer
                }
            }
        }
    }

    // Busy indicator
    BusyIndicator {
        anchors.centerIn: parent
        // running property binding seems broken, only dynamic binding assignment works
        Component.onCompleted: {
            running = Qt.binding(function() {
                return (root.usePanoramaViewer === true && imgContainer.image && imgContainer.image.allImagesLoaded === false)
                       || (imgContainer.image && imgContainer.image.imageStatus === Image.Loading)
            })
        }
        // disable the visibility when unused to avoid stealing the mouseEvent to the image color picker
        visible: running

        onVisibleChanged: {
            if (panoramaViewerLoader.active)
                fit()
        }
    }

    // Actions for RGBA filters
    Action {
        id: rFilterAction

        shortcut: "R"
        onTriggered: {
            if (hdrImageToolbar.channelModeValue !== 'r') {
                hdrImageToolbar.channelModeValue = 'r'
            } else {
                hdrImageToolbar.channelModeValue = 'rgba'
            }
        }
    }

    Action {
        id: gFilterAction

        shortcut: "G"
        onTriggered: {
            if (hdrImageToolbar.channelModeValue !== 'g') {
                hdrImageToolbar.channelModeValue = 'g'
            } else {
                hdrImageToolbar.channelModeValue = 'rgba'
            }
        }
    }

    Action {
        id: bFilterAction

        shortcut: "B"
        onTriggered: {
            if (hdrImageToolbar.channelModeValue !== 'b') {
                hdrImageToolbar.channelModeValue = 'b'
            } else {
                hdrImageToolbar.channelModeValue = 'rgba'
            }
        }
    }

    Action {
        id: aFilterAction

        shortcut: "A"
        onTriggered: {
            if (hdrImageToolbar.channelModeValue !== 'a') {
                hdrImageToolbar.channelModeValue = 'a'
            } else {
                hdrImageToolbar.channelModeValue = 'rgba'
            }
        }
    }

    // Actions for Metadata overlay
    Action {
        id: metadataAction

        shortcut: "I"
        onTriggered: {
            metadataCB.checked = !metadataCB.checked
        }
    }
}
