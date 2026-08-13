import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String enteredPin = "";
  String? savedPin;
  bool isFirstTime = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadPin();
  }

  // ✅ Load saved PIN
  Future<void> loadPin() async {
    final prefs = await SharedPreferences.getInstance();
    savedPin = prefs.getString("app_pin");

    setState(() {
      isFirstTime = savedPin == null;
      isLoading = false;
    });
  }

  // ✅ Save PIN
  Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("app_pin", pin);
  }

  // ✅ Delete PIN (Reset)
  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("app_pin");

    setState(() {
      enteredPin = "";
      isFirstTime = true;
    });
  }

  // ✅ Number Press Logic
  void onNumberPress(String number) async {
    if (enteredPin.length >= 4) return;

    setState(() {
      enteredPin += number;
    });

    if (enteredPin.length == 4) {
      await Future.delayed(const Duration(milliseconds: 200));

      if (isFirstTime) {
        await savePin(enteredPin);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("PIN Set Successfully")),
        );

        Navigator.pushReplacementNamed(context, "/home");
      } else {
        if (enteredPin == savedPin) {
          Navigator.pushReplacementNamed(context, "/home");
        } else {
          setState(() {
            enteredPin = "";
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Wrong PIN")),
          );
        }
      }
    }
  }

  void deletePin() {
    if (enteredPin.isEmpty) return;

    setState(() {
      enteredPin = enteredPin.substring(0, enteredPin.length - 1);
    });
  }

  // 🔵 PIN DOTS
  Widget buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(8),
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: index < enteredPin.length
                ? Colors.red
                : Colors.grey.shade700,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  // 🔘 NUMBER BUTTON
  Widget buildNumberButton(String number) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: () => onNumberPress(number),
      child: Container(
        margin: const EdgeInsets.all(10),
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: theme.cardColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Text(
            number,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // 🔁 RESET PIN OPTION
  Widget resetButton() {
    return TextButton(
      onPressed: clearPin,
      child: Text(
        "Forgot PIN?",
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ⏳ LOADING FIX
    if (isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: scheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isFirstTime ? "Set Your PIN" : "Enter PIN",
            style: TextStyle(color: scheme.onSurface, fontSize: 22),
          ),

          const SizedBox(height: 20),

          buildPinDots(),

          const SizedBox(height: 20),

          if (!isFirstTime) resetButton(),

          const SizedBox(height: 30),

          // 🔢 NUMPAD
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              ...List.generate(9, (index) {
                return buildNumberButton("${index + 1}");
              }),
              buildNumberButton("0"),
              GestureDetector(
                onTap: deletePin,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Icon(Icons.backspace, color: Colors.white),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}