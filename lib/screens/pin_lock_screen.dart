import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class PinLockScreen extends StatefulWidget {
  final bool isRecoveryMode;
  final VoidCallback? onAuthenticated;
  const PinLockScreen(
      {super.key, this.isRecoveryMode = false, this.onAuthenticated});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final List<String> _enteredPin = [];
  bool _isRecovering = false;
  final _answerController = TextEditingController();
  String _errorText = '';

  void _onKeyPress(String key) {
    final appState = context.read<AppState>();
    final targetLength = appState.customPinHash.length;

    setState(() {
      _errorText = '';
      if (key == 'back') {
        if (_enteredPin.isNotEmpty) _enteredPin.removeLast();
      } else {
        if (_enteredPin.length < targetLength) _enteredPin.add(key);
      }
    });

    if (_enteredPin.length == targetLength) {
      _verifyPin();
    }
  }

  void _verifyPin() {
    final appState = context.read<AppState>();
    final entered = _enteredPin.join();

    if (entered == appState.customPinHash) {
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.pop(context, true);
      }
    } else {
      setState(() {
        _enteredPin.clear();
        _errorText = 'Incorrect PIN';
      });
    }
  }

  void _handleRecovery() {
    final appState = context.read<AppState>();
    if (_answerController.text.toLowerCase().trim() ==
        appState.securityAnswer) {
      appState.resetCustomPin();
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        Navigator.pop(context, true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App Lock Reset Successful')),
      );
    } else {
      setState(() {
        _errorText = 'Incorrect Answer';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withValues(alpha: 0.8)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_person, size: 80, color: Colors.blue),
                  const SizedBox(height: 24),
                  Text(
                    _isRecovering ? 'Reset App Lock' : 'Enter App PIN',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  if (!_isRecovering) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:
                          List.generate(appState.customPinHash.length, (index) {
                        bool isFilled = index < _enteredPin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled
                                ? Colors.blue
                                : Colors.grey.withValues(alpha: 0.3),
                            border: Border.all(color: Colors.blue),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    if (_errorText.isNotEmpty)
                      Text(_errorText,
                          style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 48),
                    _buildNumPad(),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => setState(() => _isRecovering = true),
                      child: const Text('Forgot PIN?',
                          style: TextStyle(color: Colors.blueAccent)),
                    ),
                  ] else ...[
                    Text(
                      'Question: ${appState.securityQuestion}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _answerController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Recovery Answer',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_errorText.isNotEmpty)
                      Text(_errorText,
                          style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _handleRecovery,
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: Colors.blue),
                      child: const Text('Reset Lock',
                          style: TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isRecovering = false),
                      child: const Text('Back to PIN',
                          style: TextStyle(color: Colors.blueAccent)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumPad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['1', '2', '3'].map((e) => _numButton(e)).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['4', '5', '6'].map((e) => _numButton(e)).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['7', '8', '9'].map((e) => _numButton(e)).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 64),
            _numButton('0'),
            _numButton('back', icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  Widget _numButton(String key, {IconData? icon}) {
    return InkWell(
      onTap: () => _onKeyPress(key),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, color: Colors.white)
              : Text(key,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
        ),
      ),
    );
  }
}
