import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class CityGateScreen {
  /// Inserts a non-dismissible full-screen overlay — not a route, so no
  /// navigator or router can pop it. Calls [onVerified] after verification.
  static void showIfNeeded(
    BuildContext context, {
    required VoidCallback onVerified,
  }) {
    if (StorageService.getBool('city_verified')) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: CityGateOverlay(
          onVerified: () {
            entry.remove();
            onVerified();
          },
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class CityGateOverlay extends StatefulWidget {
  final VoidCallback onVerified;
  const CityGateOverlay({super.key, required this.onVerified});

  @override
  State<CityGateOverlay> createState() => _CityGateOverlayState();
}

class _CityGateOverlayState extends State<CityGateOverlay>
    with WidgetsBindingObserver {
  final _cityCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;
  bool _blocked = false;
  bool _gpsMismatch = false;
  bool _verified = false;

  static const double _puneLat = 18.5204;
  static const double _puneLng = 73.8567;
  static const double _puneRadiusM = 50000.0;

  @override
  void initState() {
    super.initState();
    // Register before the router so didPopRoute fires first
    WidgetsBinding.instance.addObserver(this);
  }

  /// Called at platform level before go_router handles back — always consume it.
  @override
  Future<bool> didPopRoute() async {
    if (!_verified) {
      if (!_blocked) {
        setState(() => _errorMsg = 'Please enter your city first.');
      }
      return true; // consumed: back gesture blocked
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) {
      setState(() => _errorMsg = 'Please enter your city name.');
      return;
    }


    setState(() {
      _loading = true;
      _errorMsg = null;
      _blocked = false;
      _gpsMismatch = false;
    });

    // City name must be Pune (case-insensitive)
    if (city.toLowerCase() != 'pune') {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _blocked = true;
      });
      return;
    }

    // City is "Pune" — verify with live GPS
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMsg =
              'Location permission is required to verify your city.\nPlease enable it in Settings and try again.';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final distM = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        _puneLat, _puneLng,
      );

      if (!mounted) return;

      if (distM <= _puneRadiusM) {
        await StorageService.setBool('city_verified', true);
        setState(() {
          _loading = false;
          _verified = true;
        });
        // Trigger onVerified (removes overlay) after brief welcome display
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) widget.onVerified();
        });
      } else {
        setState(() {
          _loading = false;
          _gpsMismatch = true; // typed "pune" but GPS places them outside Pune
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg =
            'Could not get your location. Please make sure GPS is enabled and try again.';
      });
    }
  }

  void _onScrimTap() {
    if (!_blocked && !_verified) {
      setState(() => _errorMsg = 'Please enter your city first.');
    }
  }

  void _clearError() {
    if (_errorMsg != null) setState(() => _errorMsg = null);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final topPad = MediaQuery.of(context).padding.top;

    // Card layer — no Material(transparent) wrapper so it does NOT absorb taps
    // outside its own opaque bounds, allowing the scrim to receive those taps.
    final card = AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 40, 24, 40 + bottomInset),
      child: Center(
        child: _blocked
              ? const _BlockedCard(key: ValueKey('blocked'))
              : _gpsMismatch
                  ? _GpsMismatchCard(
                      key: const ValueKey('gps'),
                      onRetry: () => setState(() {
                        _gpsMismatch = false;
                        _errorMsg = null;
                        _cityCtrl.clear();
                      }),
                    )
                  : _verified
                      ? const _VerifiedCard(key: ValueKey('verified'))
                      : _InputCard(
                          key: const ValueKey('input'),
                          ctrl: _cityCtrl,
                          loading: _loading,
                          errorMsg: null, // shown in floating banner instead
                          onVerify: () {
                            _clearError();
                            _verify();
                          },
                        ),
      ),
    );

    return Stack(
      children: [
        // Scrim: full-screen, absorbs every tap that the card doesn't claim
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onScrimTap,
            child: Container(color: Colors.black.withValues(alpha: 0.65)),
          ),
        ),
        // Card sits on top — its own opaque hit areas take priority
        card,
        // Floating error banner: visible regardless of which card state is shown
        if (_errorMsg != null)
          Positioned(
            top: topPad + 16,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── City input card ──────────────────────────────────────────────────────────
class _InputCard extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final String? errorMsg;
  final VoidCallback onVerify;

  const _InputCard({
    super.key,
    required this.ctrl,
    required this.loading,
    required this.errorMsg,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: AppColors.gradient),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_city_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Where are you located?',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your city to verify you\'re in our service area.',
              style: TextStyle(color: AppColors.gray, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'City',
                hintText: 'e.g. Pune',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => onVerify(),
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 10),
              Text(
                errorMsg!,
                style:
                    const TextStyle(color: AppColors.danger, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: loading ? null : onVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Verify Location',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GPS mismatch card (typed Pune but GPS says otherwise) ───────────────────
class _GpsMismatchCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _GpsMismatchCard({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wrong_location_rounded,
                  color: AppColors.danger, size: 42),
            ),
            const SizedBox(height: 22),
            const Text(
              'Location Mismatch',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              'You entered Pune, but your GPS shows you\'re currently outside Pune.\n\nPlease make sure you\'re physically in Pune and try again.',
              style: TextStyle(
                  fontSize: 14, color: AppColors.gray, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Blocked card (city ≠ Pune) ───────────────────────────────────────────────
class _BlockedCard extends StatelessWidget {
  const _BlockedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded,
                  color: AppColors.warning, size: 42),
            ),
            const SizedBox(height: 22),
            const Text(
              'Not Available Yet',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              'We are still not available in your city.\nWe will be there soon! 🚀',
              style: TextStyle(
                  fontSize: 15, color: AppColors.gray, height: 1.65),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                '📍  Currently serving: Pune only',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Verified / welcome card ──────────────────────────────────────────────────
class _VerifiedCard extends StatelessWidget {
  const _VerifiedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 50),
            ),
            const SizedBox(height: 22),
            const Text(
              'Welcome to Workmate4u! 🎉',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "Great news — you're in Pune!\nTaking you to the app…",
              style: TextStyle(
                  fontSize: 15, color: AppColors.gray, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
