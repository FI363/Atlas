import 'package:flutter/foundation.dart';

/// Manages real-time Atlas Agent loop state, tool call history, permission requests,
/// and proposed diff reviews.
class AgentState extends ChangeNotifier {
  bool _isAgentRunning = false;
  String _currentStatus = '';
  int _currentIteration = 0;
  final int _maxIterations = 25;

  final List<Map<String, dynamic>> _toolCalls = [];
  Map<String, dynamic>? _pendingApproval;
  Map<String, dynamic>? _pendingDiff;

  bool get isAgentRunning => _isAgentRunning;
  String get currentStatus => _currentStatus;
  int get currentIteration => _currentIteration;
  int get maxIterations => _maxIterations;

  List<Map<String, dynamic>> get toolCalls => List.unmodifiable(_toolCalls);
  Map<String, dynamic>? get pendingApproval => _pendingApproval;
  Map<String, dynamic>? get pendingDiff => _pendingDiff;

  void startAgent(String prompt) {
    _isAgentRunning = true;
    _currentStatus = 'Initializing agent...';
    _currentIteration = 0;
    _toolCalls.clear();
    _pendingApproval = null;
    _pendingDiff = null;
    notifyListeners();
  }

  void updateProgress(String status) {
    _currentStatus = status;
    notifyListeners();
  }

  void addToolCall(Map<String, dynamic> info) {
    _toolCalls.add({
      'id': info['id'] ?? '',
      'toolName': info['toolName'] ?? '',
      'args': info['args'] ?? {},
      'iteration': info['iteration'] ?? 1,
      'status': 'running',
      'result': null,
    });
    _currentIteration = info['iteration'] is int ? info['iteration'] as int : _currentIteration;
    notifyListeners();
  }

  void completeToolCall(Map<String, dynamic> info) {
    final id = info['id'] as String?;
    final index = _toolCalls.indexWhere((tc) => tc['id'] == id);
    if (index != -1) {
      _toolCalls[index]['status'] = info['result']?['permissionDenied'] == true ? 'denied' : 'completed';
      _toolCalls[index]['result'] = info['result'];
    }
    notifyListeners();
  }

  void requestApproval(Map<String, dynamic> approvalInfo) {
    _pendingApproval = approvalInfo;
    notifyListeners();
  }

  void clearApproval() {
    _pendingApproval = null;
    notifyListeners();
  }

  void proposeDiff(Map<String, dynamic> diffInfo) {
    _pendingDiff = diffInfo;
    notifyListeners();
  }

  void clearDiff() {
    _pendingDiff = null;
    notifyListeners();
  }

  void finishAgent(String response) {
    _isAgentRunning = false;
    _currentStatus = 'Task completed.';
    _pendingApproval = null;
    _pendingDiff = null;
    notifyListeners();
  }

  void cancelAgent() {
    _isAgentRunning = false;
    _currentStatus = 'Agent cancelled.';
    _pendingApproval = null;
    _pendingDiff = null;
    notifyListeners();
  }
}
