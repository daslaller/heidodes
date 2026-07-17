import 'dart:math';

import 'package:fl_nodes_core/src/constants.dart';
import 'package:fl_nodes_core/src/core/controller/overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import 'package:fl_nodes_core/src/styles/styles.dart';
import 'package:fl_nodes_core/src/core/containers/spatial_hash_grid.dart';
import 'package:fl_nodes_core/src/core/events/bus.dart';
import 'package:fl_nodes_core/src/core/events/events.dart';
import 'package:fl_nodes_core/src/core/models/config.dart';
import 'package:fl_nodes_core/src/core/models/data.dart';
import 'package:fl_nodes_core/src/core/utils/misc/nodes.dart';
import 'package:fl_nodes_core/src/core/utils/rendering/renderbox.dart';
import 'package:fl_nodes_core/src/core/controller/callback.dart';
import 'package:fl_nodes_core/src/core/controller/clipboard.dart';
import 'package:fl_nodes_core/src/core/controller/history.dart';
import 'package:fl_nodes_core/src/core/controller/project.dart';
import 'package:fl_nodes_core/src/core/controller/runner.dart';

export '../models/config.dart';

/// A controller class for the Node Editor.
///
/// This class is responsible for managing the state of the node editor,
/// including the nodes, links, and the viewport. It also provides methods
/// for adding, removing, and manipulating nodes and links.
///
/// The controller also provides an event bus for the node editor, allowing
/// different parts of the application to communicate with each other by
/// sending and receiving events.
class FlNodesController with ChangeNotifier {
  final FlCallback? onCallback;
  final GlobalKey editorKey;
  final String appVersion;

  FlNodesController({
    required this.appVersion,
    this.config = const FlNodesConfig(),
    this.style = const FlNodesStyle(),
    ProjectSaver? projectSaver,
    ProjectLoader? projectLoader,
    ProjectCreator? projectCreator,
    this.onCallback,
    GlobalKey? editorKey,
  }) : editorKey = editorKey ?? GlobalKey() {
    clipboard = FlNodesClipboardHelper(this);
    runner = FlNodesExecutionHelper(this);
    history = FlNodesHistoryHelper(this);
    project = FlNodesProjectHelper(
      this,
      projectSaver: projectSaver,
      projectLoader: projectLoader,
      projectCreator: projectCreator,
    );
    overlay = FlNodesOverlayHelper(this);
  }

  /// This method is used to dispose of the node editor controller and all of its resources, subsystems and members.
  @override
  void dispose() {
    history.clear();
    project.clear();
    runner.clear();
    overlay.clear();
    eventBus.close();

    _stopActiveLinksTicker();
    _activeLinksAnimController?.dispose();
    _activeLinksAnimController = null;

    clear();

    super.dispose();
  }

  /// This method is used to clear the core controller and all of its subsystems.
  void clear() {
    nodesSpatialHashGrid.clear();
    selectedNodeIds.clear();
    selectedLinkIds.clear();

    unboundNodeOffsets.clear();
    dragProxyOffsets.clear();
    activeLinkIds.clear();
    _effectLinkIds.clear();
    _dragActiveLinkIds.clear();
    _isDraggingSelection = false;
    _dragTotalDelta = Offset.zero;
    _stopActiveLinksTicker();

    linksDataDirty = true;
    nodesDataDirty = true;
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Controller subsystems are used to manage the state of the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  /// The event bus is used to communicate between different susbsystems and with the UI.
  final eventBus = NodeEditorEventBus();

  late final FlNodesClipboardHelper clipboard;
  late final FlNodesExecutionHelper runner;
  late final FlNodesHistoryHelper history;
  late final FlNodesProjectHelper project;
  late final FlNodesOverlayHelper overlay;

  ////////////////////////////////////////////////////////////////////////////////
  /// Animation properties are used to manage animations in the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  TickerProvider? _tickerProvider;

  late AnimationController _viewportOffsetAnimController;
  late AnimationController _viewportZoomAnimController;
  late Animation<Offset> _viewportOffsetAnim;
  late Animation<double> _viewportZoomAnim;

  AnimationController? _activeLinksAnimController;
  bool _activeLinksTickerRunning = false;

  /// Animation value for [ActiveLinksPainter] effects (0..1 repeating).
  double get activeLinksAnimationValue => _activeLinksAnimController?.value ?? 0.0;

  void setTickerProvider(TickerProvider tickerProvider) {
    _tickerProvider = tickerProvider;

    _viewportOffsetAnimController = AnimationController(
      vsync: _tickerProvider!,
    );
    _viewportZoomAnimController = AnimationController(
      vsync: _tickerProvider!,
    );

    _activeLinksAnimController = AnimationController(
      vsync: _tickerProvider!,
      duration: const Duration(seconds: 1),
    )..addListener(_onActiveLinksTick);

    if (activeLinkIds.isNotEmpty) {
      _startActiveLinksTicker();
    }
  }

  void _onActiveLinksTick() {
    // Paint-only: never set linksDataDirty from the ticker.
    eventBus.emit(
      FlActiveLinksTickEvent(id: const Uuid().v4()),
    );
  }

  void _startActiveLinksTicker() {
    final AnimationController? controller = _activeLinksAnimController;
    if (controller == null || _activeLinksTickerRunning) return;
    _activeLinksTickerRunning = true;
    controller.repeat();
  }

  void _stopActiveLinksTicker() {
    final AnimationController? controller = _activeLinksAnimController;
    if (controller == null || !_activeLinksTickerRunning) return;
    _activeLinksTickerRunning = false;
    controller.stop();
    controller.value = 0.0;
  }

  void _syncActiveLinksTicker() {
    if (activeLinkIds.isEmpty) {
      _stopActiveLinksTicker();
    } else {
      _startActiveLinksTicker();
    }
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Viewport properties are used to manage the viewport of the node editor.
  ////////////////////////////////////////////////////////////////////////////////

  final ValueNotifier<Offset> viewportOffsetNotifier = ValueNotifier(Offset.zero);
  final ValueNotifier<double> viewportZoomNotifier = ValueNotifier(1.0);

  Offset get viewportOffset => viewportOffsetNotifier.value;
  double get viewportZoom => viewportZoomNotifier.value;

  /// This method is used to set the offset of the viewport.
  ///
  /// The 'animate' parameter is used to animate the transition to the new offset.
  /// The 'absolute' parameter is used to choose whether the offset is added to the the current
  /// offset or set as an absolute value. The 'isHandled' parameter is used to indicate whether
  void setViewportOffset(
    Offset offset, {
    bool animate = true,
    bool absolute = false,
    bool isHandled = false,
  }) {
    if (viewportOffset == offset) return;

    _viewportOffsetAnimController.stop();

    final Offset beginOffset = viewportOffset;

    final Offset tempOffset = absolute ? offset : offset + beginOffset;

    final Offset endOffset = Offset(
      tempOffset.dx.clamp(
        -config.maxPanX,
        config.maxPanX,
      ),
      tempOffset.dy.clamp(
        -config.maxPanY,
        config.maxPanY,
      ),
    );

    if (animate) {
      _viewportOffsetAnimController.reset();

      final double distance = (offset - endOffset).distance;
      final double durationFactor = (distance / 1000).clamp(0.5, 3.0);

      _viewportOffsetAnimController.duration = Duration(
        milliseconds: (1000 * durationFactor).toInt(),
      );

      _viewportOffsetAnim = Tween<Offset>(
        begin: beginOffset,
        end: endOffset,
      ).animate(
        CurvedAnimation(
          parent: _viewportOffsetAnimController,
          curve: Curves.easeOut,
        ),
      )..addListener(() {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            viewportOffsetNotifier.value = _viewportOffsetAnim.value;

            eventBus.emit(
              FlViewportOffsetEvent(
                id: const Uuid().v4(),
                _viewportOffsetAnim.value,
                animate: animate,
                isHandled: isHandled,
              ),
            );
          });
        });

      _viewportOffsetAnimController.forward();
    } else {
      viewportOffsetNotifier.value = endOffset;

      eventBus.emit(
        FlViewportOffsetEvent(
          id: const Uuid().v4(),
          endOffset,
          animate: animate,
          isHandled: isHandled,
        ),
      );
    }
  }

  /// This method is used to set the zoom level of the viewport.
  ///
  /// The 'animate' parameter is used to animate the zoom transition.
  ///
  /// NOTE: The focal point deafults to the current viewport offset if not provided and uses cursor position from mouse events.
  void setViewportZoom(
    double zoom, {
    bool animate = true,
    bool absolute = false,
    bool isHandled = false,
  }) {
    if (viewportZoom == zoom) return;

    _viewportZoomAnimController.stop();

    final double beginZoom = viewportZoom;

    final double endZoom = (absolute ? zoom : viewportZoom + zoom).clamp(
      config.minZoom,
      config.maxZoom,
    );

    if (animate) {
      _viewportZoomAnimController.reset();

      _viewportZoomAnimController.duration = const Duration(milliseconds: 200);

      _viewportZoomAnim = Tween<double>(
        begin: beginZoom,
        end: endZoom,
      ).animate(
        CurvedAnimation(
          parent: _viewportZoomAnimController,
          curve: Curves.easeOut,
        ),
      )..addListener(() {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            lodLevelNotifier.value = _computeLODLevel(viewportZoom);
            viewportZoomNotifier.value = _viewportZoomAnim.value;

            eventBus.emit(
              FlViewportZoomEvent(
                id: const Uuid().v4(),
                _viewportZoomAnim.value,
                animate: animate,
                isHandled: isHandled,
              ),
            );
          });
        });

      _viewportZoomAnimController.forward();
    } else {
      lodLevelNotifier.value = _computeLODLevel(endZoom);
      viewportZoomNotifier.value = endZoom;

      eventBus.emit(
        FlViewportZoomEvent(
          id: const Uuid().v4(),
          endZoom,
          animate: animate,
          isHandled: isHandled,
        ),
      );
    }
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Rendering accelerators are data stored in the controller to speed up rendering.
  ////////////////////////////////////////////////////////////////////////////////

  late final lodLevelNotifier = ValueNotifier<int>(_computeLODLevel(viewportZoom));
  int get lodLevel => lodLevelNotifier.value;

  bool nodesDataDirty = false;
  bool linksDataDirty = false;

  void forceNodeRepaint() {
    nodesDataDirty = true;
  }

  void forceLinkRepaint() {
    linksDataDirty = true;
  }

  /// This method is used to compute the level of detail (LOD) based on the zoom level and
  /// it's called automatically by the controller when the zoom level is changed.
  static int _computeLODLevel(double zoom) {
    if (zoom > 0.5) {
      return 4;
    } else if (zoom > 0.25) {
      return 3;
    } else if (zoom > 0.125) {
      return 2;
    } else if (zoom > 0.0625) {
      return 1;
    } else {
      return 0;
    }
  }

  ////////////////////////////////////////////////////////////////////////////////
  /// Node editor configuration and style.
  ////////////////////////////////////////////////////////////////////////////////

  FlNodesConfig config;

  /// Set the global configuration of the node editor.
  void setConfig(FlNodesConfig config) {
    if (config == this.config) return;

    this.config = config;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      FlConfigurationChangeEvent(
        config,
        id: const Uuid().v4(),
      ),
    );
  }

  /// Quick access to frequently used configuration properties.

  /// Enable or disable zooming in the node editor.
  void enableSnapToGrid(bool enable) {
    if (!enable) {
      for (final FlNodeDataModel node in nodes.values) {
        node.offset = unboundNodeOffsets[node.id]!;
      }
    } else {
      for (final FlNodeDataModel node in nodes.values) {
        node.offset = Offset(
          (node.offset.dx / config.snapToGridSize).round() * config.snapToGridSize,
          (node.offset.dy / config.snapToGridSize).round() * config.snapToGridSize,
        );
      }
    }

    setConfig(config.copyWith(enableSnapToGrid: enable));
  }

  /// Set the size of the grid to snap to in the node editor.
  void setSnapToGridSize(double size) => setConfig(config.copyWith(snapToGridSize: size));

  /// Enable or disable auto placement of nodes in the node editor.
  void enableAutoPlacement(bool enable) =>
      setConfig(config = config.copyWith(enableAutoPlacement: enable));

  FlNodesStyle style;

  /// Set the style of the node editor.
  void setStyle(FlNodesStyle style) {
    if (style == this.style) return;

    this.style = style;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      FlStyleChangeEvent(
        style,
        id: const Uuid().v4(),
      ),
    );
  }

  ////////////////////////////////////////////////////////////////////////
  /// Localization.
  ////////////////////////////////////////////////////////////////////////

  Locale locale = const Locale('en');

  /// Set the locale of the node editor.
  void setLocale(Locale locale) {
    if (locale == this.locale) return;

    this.locale = locale;

    nodesDataDirty = true;
    linksDataDirty = true;

    eventBus.emit(
      FlLocaleChangeEvent(
        locale,
        id: const Uuid().v4(),
      ),
    );
  }

  ////////////////////////////////////////////////////////////////////////
  /// Nodes and links management.
  ////////////////////////////////////////////////////////////////////////

  Map<String, FlNodePrototype> nodePrototypes = {};
  List<FlNodePrototype> get nodePrototypesAsList => nodePrototypes.values.map((e) => e).toList();
  int get nodePrototypeCount => nodePrototypes.length;

  Map<String, FlNodeDataModel> get nodes => project.projectData.nodes;
  List<FlNodeDataModel> get nodesAsList => nodes.values.toList();
  int get nodeCount => nodes.length;

  Map<String, FlLinkDataModel> get links => project.projectData.links;
  List<FlLinkDataModel> get linksAsList => project.projectData.links.values.toList();
  int get linkCount => links.length;

  final SpatialHashGrid nodesSpatialHashGrid = SpatialHashGrid(
    cellSize: kNodesSpatialHashingCellSize,
  );

  /// This map holds the raw nodes offsets before they are snapped to the grid.
  final Map<String, Offset> unboundNodeOffsets = {};

  /// Live drag paint offsets (committed to [node.offset] only on drag end).
  final Map<String, Offset> dragProxyOffsets = {};

  /// Links currently painted by the active tier (effects and/or drag-tracked).
  final Set<String> activeLinkIds = {};

  /// Links kept active because they have an assigned [FlLinkEffect].
  final Set<String> _effectLinkIds = {};

  /// Links kept active only for the duration of a selection drag.
  final Set<String> _dragActiveLinkIds = {};

  bool _isDraggingSelection = false;
  Offset _dragTotalDelta = Offset.zero;
  bool get isDraggingSelection => _isDraggingSelection;

  /// Resolved paint position: proxy during drag, else committed [FlNodeDataModel.offset].
  Offset nodePaintOffset(String nodeId) {
    final Offset? proxy = dragProxyOffsets[nodeId];
    if (proxy != null) return proxy;
    return nodes[nodeId]?.offset ?? Offset.zero;
  }

  /// Registers [linkId] as effect-driven on the active tier.
  void setLinkEffect(String linkId, {required bool enabled}) {
    if (!links.containsKey(linkId)) return;

    if (enabled) {
      _effectLinkIds.add(linkId);
    } else {
      _effectLinkIds.remove(linkId);
    }
    _rebuildActiveLinkIds();
    linksDataDirty = true;
    eventBus.emit(FlActiveLinksMembershipEvent(id: const Uuid().v4()));
  }

  /// Keeps links whose resolved [FlLinkStyle.effect] is set on the active tier.
  void _syncLinkEffectMembership(FlLinkDataModel link) {
    final FlPortDataModel? port1 =
        nodes[link.ports.$1.nodeId]?.ports[link.ports.$1.portId];
    if (port1 == null) {
      _effectLinkIds.remove(link.id);
      return;
    }

    final FlLinkStyle style = port1.style.linkStyleBuilder(link.state);
    if (style.effect != null) {
      _effectLinkIds.add(link.id);
    } else {
      _effectLinkIds.remove(link.id);
    }
  }

  /// Recomputes effect membership for every link (e.g. after project load).
  void resyncLinkEffects() {
    _effectLinkIds.clear();
    for (final FlLinkDataModel link in links.values) {
      _syncLinkEffectMembership(link);
    }
    _rebuildActiveLinkIds();
    linksDataDirty = true;
    eventBus.emit(FlActiveLinksMembershipEvent(id: const Uuid().v4()));
  }

  void addActiveLinks(Iterable<String> linkIds) {
    var changed = false;
    for (final id in linkIds) {
      if (activeLinkIds.add(id)) changed = true;
    }
    if (changed) {
      _syncActiveLinksTicker();
      linksDataDirty = true;
      eventBus.emit(FlActiveLinksMembershipEvent(id: const Uuid().v4()));
    }
  }

  void removeActiveLinks(Iterable<String> linkIds) {
    var changed = false;
    for (final id in linkIds) {
      if (_effectLinkIds.contains(id)) continue;
      if (activeLinkIds.remove(id)) changed = true;
      _dragActiveLinkIds.remove(id);
    }
    if (changed) {
      _syncActiveLinksTicker();
      linksDataDirty = true;
      eventBus.emit(FlActiveLinksMembershipEvent(id: const Uuid().v4()));
    }
  }

  void _rebuildActiveLinkIds() {
    activeLinkIds
      ..clear()
      ..addAll(_effectLinkIds)
      ..addAll(_dragActiveLinkIds);
    _syncActiveLinksTicker();
  }

  bool isNodePresent(String id) => nodes.containsKey(id);

  bool isLinkPresent(String id) => links.containsKey(id);

  bool isNodeSelected(String id) => selectedNodeIds.contains(id);
  bool isNodeCollapsed(String id) => nodes[id]?.state.isCollapsed ?? false;
  bool isNodeHovered(String id) => nodes[id]?.state.isHovered ?? false;

  bool isLinkSelected(String id) => selectedLinkIds.contains(id);

  FlNodeDataModel? getNodeById(String id) => nodes[id];
  FlLinkDataModel? getLinkById(String id) => project.projectData.links[id];

  /// This method is used to register a node prototype with the node editor.
  ///
  /// NOTE: node prototypes are identified by human-readable strings instead of UUIDs.
  void registerNodePrototype(FlNodePrototype prototype) {
    nodePrototypes.putIfAbsent(
      prototype.idName,
      () => prototype,
    );
  }

  /// This method is used to remove a node prototype by its name.
  ///
  /// NOTE: node prototypes are identified by human-readable strings instead of UUIDs.
  void unregisterNodePrototype(String name) {
    if (!nodePrototypes.containsKey(name)) {
      throw Exception('Node prototype $name does not exist.');
    } else {
      nodePrototypes.remove(name);
    }
  }

  /// This method is used to add a [FlNodeDataModel] to the node editor by its prototype name.
  ///
  /// The method takes the name of the node prototype and creates an instance of the node
  /// based on the prototype. The method also takes an optional offset parameter to set the
  /// initial position of the node in the node editor. The node is also inserted into the
  /// spatial hash grid for efficient querying of nodes based on their positions
  ///
  /// See [SpatialHashGrid] and [selectNodesByArea].
  ///
  /// Emits an [FlAddNodeEvent] event.
  FlNodeDataModel addNode(
    String name, {
    Offset offset = Offset.zero,
    Map<String, PortLocator>? links,
    Map<String, dynamic>? customData,
  }) {
    if (!nodePrototypes.containsKey(name)) {
      throw Exception('Node prototype $name does not exist.');
    }

    if (config.enableSnapToGrid) {
      offset = Offset(
        (offset.dx / config.snapToGridSize).round() * config.snapToGridSize,
        (offset.dy / config.snapToGridSize).round() * config.snapToGridSize,
      );
    }

    final FlNodeDataModel instance = createNode(
      nodePrototypes[name]!,
      controller: this,
      offset: offset,
      customData: customData,
    );

    nodes.putIfAbsent(instance.id, () => instance);
    unboundNodeOffsets.putIfAbsent(instance.id, () => instance.offset);

    if (links != null) {
      for (final MapEntry<String, PortLocator> entry in links.entries) {
        final String fromPortIdName = entry.key;
        final PortLocator toPortLocator = entry.value;

        final FlLinkDataModel? link = addLink(
          instance.id,
          fromPortIdName,
          toPortLocator.nodeId,
          toPortLocator.portId,
        );

        if (link == null) {
          onCallback?.call(
            FlCallbackType.error,
            'Failed to create link from node ${instance.id} port $fromPortIdName '
            'to node ${toPortLocator.nodeId} port ${toPortLocator.portId}',
          );
        }
      }
    }

    nodesDataDirty = true;

    eventBus.emit(
      FlAddNodeEvent(id: const Uuid().v4(), instance),
    );

    return instance;
  }

  /// This method is used to add a node from an existing node object.
  ///
  /// This method is used when loading a project from a file or in copy/paste operations
  /// and preserves all properties of the node object.
  ///
  /// Emits an [FlAddNodeEvent] event.
  void addNodeFromExisting(
    FlNodeDataModel node, {
    bool isHandled = false,
    String? eventId,
  }) {
    if (nodes.containsKey(node.id)) return;

    Offset offset = node.offset;

    if (config.enableSnapToGrid) {
      offset = Offset(
        (offset.dx / config.snapToGridSize).round() * config.snapToGridSize,
        (offset.dy / config.snapToGridSize).round() * config.snapToGridSize,
      );
    }

    nodes.putIfAbsent(node.id, () => node.copyWith(offset: offset));

    unboundNodeOffsets.putIfAbsent(node.id, () => node.offset);

    if (node.state.isSelected) selectedNodeIds.add(node.id);

    nodesDataDirty = true;

    eventBus.emit(
      FlAddNodeEvent(
        id: eventId ?? const Uuid().v4(),
        node,
        isHandled: isHandled,
      ),
    );

    for (final FlPortDataModel port in node.ports.values) {
      for (final FlLinkDataModel link in port.links) {
        addLinkFromExisting(link, isHandled: isHandled);
      }
    }
  }

  /// This method is used to remove a node by its ID.
  ///
  /// Emits a [FlRemoveNodeEvent] event.
  Future<void> removeNodeById(
    String id, {
    String? eventId,
    bool isHandled = false,
  }) async {
    if (!nodes.containsKey(id)) return;

    final FlNodeDataModel node = nodes[id]!;

    for (final FlPortDataModel port in node.ports.values) {
      final List<String> linksToRemove = port.links.map((link) => link.id).toList();

      for (final linkId in linksToRemove) {
        removeLinkById(linkId, isHandled: true);
      }
    }

    nodes.remove(id);

    // selectedNodeIds.remove(id); We don't remove the node from the selected nodes because you might be iterating over them.

    // The links data is set to dirty by the removeLinkById method.
    nodesDataDirty = true;

    eventBus.emit(
      FlRemoveNodeEvent(
        id: eventId ?? const Uuid().v4(),
        node,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to add a link between two ports.
  ///
  /// The method takes the IDs of the two nodes and the two ports and creates a link
  /// between them. The method also checks if the link is valid based on the port types
  /// and the number of links allowed on each port. Moreover, the method enforces the
  /// direction of the link based on the port types, i.e., an output port can only be
  /// connected to an input port guaranteeing that the graph is directed the right way.
  ///
  /// Emits an [FlAddLinkEvent] event.
  FlLinkDataModel? addLink(
    String node1Id,
    String port1IdName,
    String node2Id,
    String port2IdName, {
    String? eventId,
  }) {
    // Check for self-links
    if (node1Id == node2Id) return null;

    final FlNodeDataModel node1 = nodes[node1Id]!;
    final FlPortDataModel port1 = node1.ports[port1IdName]!;
    final FlNodeDataModel node2 = nodes[node2Id]!;
    final FlPortDataModel port2 = node2.ports[port2IdName]!;

    // if this exact link already exists, don't do anything
    if (FlNodesUtils.linkExists(
      node1Id,
      port1IdName,
      node2Id,
      port2IdName,
      links.values.toList(),
    )) {
      onCallback?.call(
        FlCallbackType.error,
        'A link already exists between node $node1Id port $port1IdName '
        'and node $node2Id port $port2IdName',
      );
      return null;
    }

    final String? errorMessage = port1.canLinkTo(port2);

    if (errorMessage != null) {
      onCallback?.call(
        FlCallbackType.error,
        errorMessage,
      );
      return null;
    }

    final link = FlLinkDataModel(
      id: const Uuid().v4(),
      ports: (
        (
          nodeId: node1Id,
          portId: port1IdName,
        ),
        (
          nodeId: node2Id,
          portId: port2IdName,
        ),
      ),
      state: FlLinkState(),
    );

    port1.links.add(link);
    port2.links.add(link);

    links.putIfAbsent(
      link.id,
      () => link,
    );

    _syncLinkEffectMembership(link);
    _rebuildActiveLinkIds();
    linksDataDirty = true;

    eventBus.emit(
      FlAddLinkEvent(id: eventId ?? const Uuid().v4(), link),
    );

    return link;
  }

  /// This method is used to add a link from an existing link object.
  ///
  /// This method is used when loading a project from a file or in copy/paste operations
  /// and preserves all properties of the link object.
  ///
  /// Emits an [FlAddLinkEvent] event.
  void addLinkFromExisting(
    FlLinkDataModel link, {
    String? eventId,
    bool isHandled = false,
  }) {
    if (!nodes.containsKey(link.ports.$1.nodeId) || !nodes.containsKey(link.ports.$2.nodeId)) {
      return;
    }

    final FlNodeDataModel node1 = nodes[link.ports.$1.nodeId]!;
    final FlNodeDataModel node2 = nodes[link.ports.$2.nodeId]!;

    if (!node1.ports.containsKey(link.ports.$1.portId) ||
        !node2.ports.containsKey(link.ports.$2.portId)) {
      return;
    }

    final FlPortDataModel port1 = nodes[link.ports.$1.nodeId]!.ports[link.ports.$1.portId]!;
    final FlPortDataModel port2 = nodes[link.ports.$2.nodeId]!.ports[link.ports.$2.portId]!;

    port1.links.add(link);
    port2.links.add(link);

    links.putIfAbsent(
      link.id,
      () => link,
    );

    if (link.state.isSelected) selectedLinkIds.add(link.id);

    _syncLinkEffectMembership(link);
    _rebuildActiveLinkIds();
    linksDataDirty = true;

    eventBus.emit(
      FlAddLinkEvent(
        id: eventId ?? const Uuid().v4(),
        link,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to remove a link by its ID.
  ///
  /// Emits a [FlRemoveLinkEvent] event.
  void removeLinkById(
    String id, {
    String? eventId,
    bool isHandled = false,
  }) {
    if (!links.containsKey(id)) return;

    final FlLinkDataModel link = links[id]!;

    // Remove the link from its associated ports
    final FlPortDataModel? port1 = nodes[link.ports.$1.nodeId]?.ports[link.ports.$1.portId];
    final FlPortDataModel? port2 = nodes[link.ports.$2.nodeId]?.ports[link.ports.$2.portId];

    port1?.links.remove(link);
    port2?.links.remove(link);

    links.remove(id);

    _effectLinkIds.remove(id);
    _dragActiveLinkIds.remove(id);
    if (activeLinkIds.remove(id)) {
      _syncActiveLinksTicker();
    }

    // selectedLinkIds.remove(id); We don't remove the link from the selected links because you might be iterating over them.

    linksDataDirty = true;

    eventBus.emit(
      FlRemoveLinkEvent(
        id: eventId ?? const Uuid().v4(),
        link,
        isHandled: isHandled,
      ),
    );
  }

  /// Represents a link in the process of being drawn.
  TempLinkDataModel? _tempLink;
  TempLinkDataModel? get tempLink => _tempLink;

  /// This method is used to draw a temporary link between two points in the node editor.
  ///
  /// Usually, this method is called when the user is dragging a link from a port to another port.
  ///
  /// Emits a [FlDrawTempLinkEvent] event.
  void drawTempLink(FlLinkStyle style, Offset startOffset, Offset endOffset) {
    _tempLink = TempLinkDataModel(
      startOffset: startOffset,
      endOffset: endOffset,
      outPortGeometricOrientation: FlPortGeometricOrientation.right,
      inPortGeometricOrientation: FlPortGeometricOrientation.left,
      linkStyle: style,
    );

    clearSelection();

    // The temp link is treated differently from regular links, so we don't need to mark the links data as dirty.

    eventBus.emit(
      FlDrawTempLinkEvent(
        id: const Uuid().v4(),
        startOffset,
        endOffset,
      ),
    );
  }

  /// This method is used to clear the temporary link from the node editor.
  ///
  /// Emits a [FlDrawTempLinkEvent] event.
  void clearTempLink() {
    _tempLink = null;

    // The temp link is treated differently from regular links, so we don't need to mark the links data as dirty.

    eventBus.emit(
      FlDrawTempLinkEvent(id: const Uuid().v4(), Offset.zero, Offset.zero),
    );
  }

  /// This method is used to break all links associated with a port.
  ///
  /// Emits a [FlRemoveLinkEvent] event for each link that is removed.
  void breakPortLinks(String nodeId, String portId, {bool isHandled = false}) {
    if (!nodes.containsKey(nodeId)) return;
    if (!nodes[nodeId]!.ports.containsKey(portId)) return;

    final FlPortDataModel port = nodes[nodeId]!.ports[portId]!;
    final List<String> linksToRemove = port.links.map((link) => link.id).toList();

    for (final linkId in linksToRemove) {
      removeLinkById(linkId, isHandled: linkId != linksToRemove.last);
    }

    linksDataDirty = true;
  }

  /// This method is used to set custom data for a node.
  ///
  /// Emits a [FlNodeCustomDataEvent] event.
  void setCustomData(
    String nodeId, {
    required String key,
    required dynamic value,
    bool needsLayout = false,
    bool needPaint = false,
    bool isHandled = false,
  }) {
    if (!nodes.containsKey(nodeId)) return;

    final FlNodeDataModel node = nodes[nodeId]!;
    node.customData[key] = value;

    if (needsLayout) {
      nodesDataDirty = true;
      linksDataDirty = true;
    } else if (needPaint) {
      nodesDataDirty = true;
    }

    if (needsLayout) {
      eventBus.emit(
        FlNodeCustomDataLayoutEvent(
          id: const Uuid().v4(),
          nodeId: nodeId,
          key: key,
          value: value,
          isHandled: isHandled,
        ),
      );
    } else if (needPaint) {
      eventBus.emit(
        FlNodeCustomDataPaintEvent(
          id: const Uuid().v4(),
          nodeId: nodeId,
          key: key,
          value: value,
          isHandled: isHandled,
        ),
      );
    } else {
      eventBus.emit(
        FlNodeCustomDataEvent(
          id: const Uuid().v4(),
          nodeId: nodeId,
          key: key,
          value: value,
          isHandled: isHandled,
        ),
      );
    }
  }

  /// This method is used to set the data of a field in a node.
  ///
  /// Emits a [FlNodeFieldEvent] event.
  void setFieldData(
    String nodeId,
    String fieldId, {
    required FlFieldEventType eventType,
    dynamic data,
  }) {
    if (eventType == FlFieldEventType.change) return;

    final FlNodeDataModel node = nodes[nodeId]!;
    final FlFieldDataModel field = node.fields[fieldId]!;
    field.data = data;

    eventBus.emit(
      FlNodeFieldEvent(
        id: const Uuid().v4(),
        nodeId,
        data,
        eventType,
      ),
    );
  }

  /// This method is used to toggle the collapse state of all selected nodes.
  ///
  /// Emit a [NodeRenderModeEvent] event.
  void toggleCollapseSelectedNodes(bool collapse) {
    for (final String id in selectedNodeIds) {
      final FlNodeDataModel? node = nodes[id];
      node?.state.isCollapsed = collapse;
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      FlCollapseNodeEvent(id: const Uuid().v4(), collapse, selectedNodeIds),
    );
  }

  ////////////////////////////////////////////////////////////////////////////
  /// Selection management.
  ///////////////////////////////////////////////////////////////////////////

  final Set<String> selectedNodeIds = {};
  final Set<String> selectedLinkIds = {};

  Rect? _highlightArea;
  Rect? get highlightArea => _highlightArea;

  /// Begins a paint-only selection drag (proxy offsets; no model commit).
  void beginDragSelection(Offset position, {String? eventId}) {
    if (selectedNodeIds.isEmpty || _isDraggingSelection) return;

    _isDraggingSelection = true;
    _dragTotalDelta = Offset.zero;

    for (final String id in selectedNodeIds) {
      final FlNodeDataModel node = nodes[id]!;
      unboundNodeOffsets.putIfAbsent(id, () => node.offset);
      dragProxyOffsets[id] = unboundNodeOffsets[id]!;
    }

    _dragActiveLinkIds
      ..clear()
      ..addAll(FlNodesUtils.getConnectedLinkIds(selectedNodeIds, nodes));
    _rebuildActiveLinkIds();

    // Membership change needs static tier to drop drag-tracked links once.
    linksDataDirty = true;

    eventBus.emit(
      FlDragSelectionStartEvent(
        selectedNodeIds.toSet(),
        position,
        id: eventId ?? const Uuid().v4(),
      ),
    );
  }

  /// Live drag delta: updates proxy offsets only (paint path).
  ///
  /// When not in an active drag (e.g. undo/redo), commits immediately.
  void dragSelection(
    Offset delta, {
    String? eventId,
    bool isWorldDelta = false,
    bool resetUnboundOffset = false,
  }) {
    if (selectedNodeIds.isEmpty) return;

    final Offset effectiveDelta = isWorldDelta ? delta : delta / viewportZoom;

    if (!_isDraggingSelection) {
      _commitSelectionDelta(
        effectiveDelta,
        eventId: eventId,
        resetUnboundOffset: resetUnboundOffset,
      );
      return;
    }

    for (final String id in selectedNodeIds) {
      final FlNodeDataModel node = nodes[id]!;

      if (resetUnboundOffset) {
        unboundNodeOffsets[id] = node.offset;
      } else {
        unboundNodeOffsets.putIfAbsent(id, () => node.offset);
      }

      unboundNodeOffsets[id] = unboundNodeOffsets[id]! + effectiveDelta;

      if (config.enableSnapToGrid) {
        final Offset unboundOffset = unboundNodeOffsets[id]!;
        dragProxyOffsets[id] = Offset(
          (unboundOffset.dx / config.snapToGridSize).round() * config.snapToGridSize,
          (unboundOffset.dy / config.snapToGridSize).round() * config.snapToGridSize,
        );
      } else {
        dragProxyOffsets[id] = unboundNodeOffsets[id]!;
      }
    }

    _dragTotalDelta += effectiveDelta;

    eventBus.emit(
      FlDragSelectionEvent(
        id: eventId ?? const Uuid().v4(),
        selectedNodeIds.toSet(),
        effectiveDelta,
      ),
    );
  }

  /// Commits proxy offsets into the model and ends the drag.
  void endDragSelection(Offset position, {String? eventId}) {
    if (!_isDraggingSelection) return;

    final Set<String> nodeIds = selectedNodeIds.toSet();
    final Offset totalDelta = _dragTotalDelta;
    final String commitId = eventId ?? const Uuid().v4();

    for (final String id in nodeIds) {
      final FlNodeDataModel? node = nodes[id];
      if (node == null) continue;

      final Offset? proxy = dragProxyOffsets[id];
      if (proxy != null) {
        node.offset = proxy;
      }
    }

    dragProxyOffsets.clear();
    _dragActiveLinkIds.clear();
    _rebuildActiveLinkIds();
    _isDraggingSelection = false;
    _dragTotalDelta = Offset.zero;

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      FlDragSelectionEndEvent(
        position,
        nodeIds,
        id: commitId,
        totalDelta: totalDelta,
      ),
    );

    if (totalDelta != Offset.zero) {
      eventBus.emit(
        FlDragSelectionCommitEvent(
          nodeIds,
          totalDelta,
          id: commitId,
        ),
      );
    }
  }

  /// Immediate model commit (undo/redo or non-gesture callers).
  void _commitSelectionDelta(
    Offset effectiveDelta, {
    String? eventId,
    bool resetUnboundOffset = false,
  }) {
    for (final String id in selectedNodeIds) {
      final FlNodeDataModel node = nodes[id]!;

      if (resetUnboundOffset) {
        unboundNodeOffsets[id] = node.offset;
      } else {
        unboundNodeOffsets.putIfAbsent(id, () => node.offset);
      }

      unboundNodeOffsets[id] = unboundNodeOffsets[id]! + effectiveDelta;

      if (config.enableSnapToGrid) {
        final Offset unboundOffset = unboundNodeOffsets[id]!;
        node.offset = Offset(
          (unboundOffset.dx / config.snapToGridSize).round() * config.snapToGridSize,
          (unboundOffset.dy / config.snapToGridSize).round() * config.snapToGridSize,
        );
      } else {
        node.offset += effectiveDelta;
      }
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      FlDragSelectionCommitEvent(
        selectedNodeIds.toSet(),
        effectiveDelta,
        id: eventId ?? const Uuid().v4(),
      ),
    );
  }

  /// This method is used to set the selection area for selecting nodes.
  ///
  /// See [selectNodesByArea] for more information.
  ///
  /// Emits a [highlightAreaEvent] event.
  void setHighlightArea(Rect? area) {
    _highlightArea = area;
    eventBus.emit(FlAreaHighlightEvent(id: const Uuid().v4(), area));
  }

  /// This method is used to select nodes by their IDs.
  ///
  /// Emits a [FlNodeSelectionEvent] event.
  void selectNodesById(
    Set<String> ids, {
    bool holdSelection = false,
    bool isHandled = false,
    bool isSideEffect = false,
  }) {
    if (ids.isEmpty) {
      return clearSelection();
    } else if (!holdSelection) {
      clearSelection();
    }

    selectedNodeIds.addAll(ids);

    for (final String id in selectedNodeIds) {
      final FlNodeDataModel? node = nodes[id];
      node?.state.isSelected = true;
    }

    eventBus.emit(
      FlNodeSelectionEvent(
        id: const Uuid().v4(),
        selectedNodeIds.toSet(),
        type: holdSelection ? FlSelectionEventType.holdSelect : FlSelectionEventType.select,
        isHandled: isHandled,
        isSideEffect: isSideEffect,
      ),
    );
  }

  /// This method is used to select nodes that are contained within the selection area.
  ///
  /// This method is used in conjunction with the [sethighlightArea] method to select
  /// nodes that are contained within the selection area. The method queries the spatial
  /// hash grid to find nodes that are within the selection area and then selects them.
  ///
  /// See [selectNodesById] for more information.
  void selectNodesByArea({bool holdSelection = false}) {
    if (_highlightArea == null || _highlightArea == Rect.zero) {
      return clearSelection();
    }

    final Set<String> containedNodes = nodesSpatialHashGrid.queryArea(_highlightArea!);

    selectNodesById(
      containedNodes,
      holdSelection: holdSelection,
    );

    _highlightArea = Rect.zero;
  }

  /// This method is used to select a link by its ID.
  ///
  /// Emits a [FlNodeSelectionEvent] event.
  void selectLinkById(
    String id, {
    bool holdSelection = false,
    bool isHandled = false,
  }) {
    if (id.isEmpty || _tempLink != null) {
      return clearSelection();
    } else if (!holdSelection) {
      clearSelection();
    }

    selectedLinkIds.add(id);

    for (final String id in selectedLinkIds) {
      final FlLinkDataModel? link = links[id];
      link?.state.isSelected = true;
    }

    linksDataDirty = true;

    eventBus.emit(
      FlLinkSelectionEvent(
        id: const Uuid().v4(),
        selectedLinkIds.toSet(),
        type: holdSelection ? FlSelectionEventType.holdSelect : FlSelectionEventType.select,
        isHandled: isHandled,
      ),
    );
  }

  /// This method is used to deselect all selected nodes.
  void clearSelection({bool isHandled = false}) {
    for (final String id in selectedNodeIds) {
      final FlNodeDataModel? node = nodes[id];
      node?.state.isSelected = false;
    }

    for (final String id in selectedLinkIds) {
      final FlLinkDataModel? link = links[id];
      link?.state.isSelected = false;
    }

    linksDataDirty = true;
    nodesDataDirty = true;

    eventBus.emit(
      FlNodeSelectionEvent(
        id: const Uuid().v4(),
        selectedNodeIds.toSet(),
        type: FlSelectionEventType.deselect,
        isHandled: isHandled,
      ),
    );

    eventBus.emit(
      FlLinkSelectionEvent(
        id: const Uuid().v4(),
        selectedLinkIds.toSet(),
        type: FlSelectionEventType.deselect,
        isHandled: isHandled,
      ),
    );

    selectedNodeIds.clear();
    selectedLinkIds.clear();
  }

  /////////////////////////////////////////////////////////////////////
  /// Miscellaneous helpers useful for node editors.
  /////////////////////////////////////////////////////////////////////

  /// This method is used to focus the viweport on a set of nodes by their IDs.
  ///
  /// The method calculates the encompassing rectangle of the nodes and then
  /// centers the viewport on the center of the rectangle. The method also
  /// calculates the zoom level required to fit all the nodes in the viewport.
  ///
  /// See [calculateEncompassingRect], [selectNodesById], [setViewportOffset], and [setViewportZoom] for more information.
  void focusNodesById(
    Set<String> ids, {
    bool holdSelection = false,
    bool animate = true,
  }) {
    selectNodesById(ids, holdSelection: holdSelection);

    final Rect encompassingRect = FlNodesUtils.calculateEncompassingRect(
      selectedNodeIds,
      nodes,
      margin: 256,
    );

    final Size nodeEditorSize = RenderBoxUtils.getSizeFromGlobalKey(editorKey)!;

    setViewportOffset(
      -encompassingRect.center,
      animate: animate,
      absolute: true,
    );

    final double fitZoom = min(
      nodeEditorSize.width / encompassingRect.width,
      nodeEditorSize.height / encompassingRect.height,
    );

    // Check if the fitZoom is valid (might be infinite or NaN if the encompassingRect has zero width or height)
    if (fitZoom.isInfinite || fitZoom.isNaN) return;

    setViewportZoom(
      fitZoom,
      absolute: true,
      animate: animate,
    );
  }

  /// This method is used to find all nodes with the specified display name.
  List<String> searchNodesByName(
    BuildContext context,
    String name,
  ) {
    final results = <String>[];

    final regex = RegExp(name, caseSensitive: false);

    for (final FlNodeDataModel node in nodes.values) {
      if (regex.hasMatch(node.prototype.displayName(context))) {
        results.add(node.id);
      }
    }

    return results;
  }
}
