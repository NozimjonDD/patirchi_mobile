import 'dart:async';

import 'package:flutter/material.dart';
import 'package:patirchi/core/constants/app_constants.dart';
import 'package:patirchi/core/constants/enums.dart';
import 'package:patirchi/core/error/result.dart';
import 'package:patirchi/features/auth/data/models/tg_login_models.dart';
import 'package:patirchi/features/auth/data/models/user_model.dart';
import 'package:patirchi/features/auth/data/repositories/auth_repository.dart';
import 'package:patirchi/features/auth/data/repositories/tg_auth_repository.dart';

/// Autentifikatsiya holati va operatsiyalarini boshqaruvchi Provider.
///
/// OTP asosidagi auth oqimi:
/// 1. [selectRole] — rol tanlash (`ordinary` / `business`)
/// 2. [login] — telefon yuborish → backend OTP yuboradi → [otpSecret] saqlanadi
/// 3. [confirmOtp] — OTP kiritish → tokenlar saqlanadi → /home ga o'tish
///
/// Ilovani qayta ishga tushirganda:
/// - [tryAutoLogin] — token bormi tekshiradi → getMe() → muvaffaqiyatli bo'lsa /home
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository})
      : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;
  final TgAuthRepository _tgRepository = TgAuthRepository();

  // ---------------------------------------------------------------------------
  // Holat
  // ---------------------------------------------------------------------------

  bool _isLoading = false;
  UserModel? _currentUser;
  String _selectedRole = 'ordinary';
  UserRole? _activeUiRole;
  String? _lastPhoneNumber;

  /// Login 1-qadam javobidan kelgan maxfiy kalit.
  String? _otpSecret;

  String? _errorMessage;

  // Telegram login holati
  TgLoginStartResponse? _tgSession;
  TgLoginStatusResponse? _tgStatus;
  Timer? _tgPollTimer;
  DateTime? _tgPollStartedAt;
  String? _tgErrorMessage;
  bool _tgPolling = false;
  int _tgConsecutiveErrors = 0;

  // ---------------------------------------------------------------------------
  // Getter'lar
  // ---------------------------------------------------------------------------

  bool get isLoading => _isLoading;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _repository.isLoggedIn;
  String get selectedRole => _selectedRole;

  /// OTP ekraniga o'tganda ishlatiladi.
  String? get otpSecret => _otpSecret;

  String? get errorMessage => _errorMessage;

  // Telegram login getter'lar
  TgLoginStartResponse? get tgSession => _tgSession;
  TgLoginStatusResponse? get tgStatus => _tgStatus;
  bool get isTgPolling => _tgPolling;
  String? get tgErrorMessage => _tgErrorMessage;

  /// Navigatsiya uchun UserRole enum qiymati.
  ///
  /// Agar foydalanuvchi profil ekranidan rolni qo'lda almashtirgan bo'lsa
  /// ([_activeUiRole]), o'sha rol ishlatiladi. Aks holda backend roli
  /// (`ordinary`, `business`, `hybrid`, `delivery`, `admin`) moslashtiriladi.
  UserRole get currentUserRole {
    if (_activeUiRole != null) return _activeUiRole!;
    final role = _currentUser?.role ?? _selectedRole;
    return switch (role) {
      'delivery' => UserRole.courier,
      'supplier' => UserRole.supplier,
      'business' || 'hybrid' => UserRole.bakery,
      _ => UserRole.buyer,
    };
  }

  // ---------------------------------------------------------------------------
  // Rol tanlash
  // ---------------------------------------------------------------------------

  /// Kirish uchun rol tanlaydi: `ordinary` yoki `business`.
  void selectRole(String role) {
    _selectedRole = role;
    _activeUiRole = null;
    notifyListeners();
  }

  /// Profil ekranidan rol almashtirish (enum asosida).
  void switchRole(UserRole role) {
    _activeUiRole = role;
    _selectedRole = switch (role) {
      UserRole.buyer => 'ordinary',
      UserRole.bakery || UserRole.supplier => 'business',
      UserRole.courier => 'delivery',
    };
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(role: _selectedRole);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Login (OTP yuborish — 1-qadam)
  // ---------------------------------------------------------------------------

  /// Telefon raqamiga OTP yuboradi.
  ///
  /// Muvaffaqiyatli bo'lsa `true` qaytaradi va [otpSecret] saqlanadi.
  /// Agar SMS xizmati xato bersa ham, vaqtinchalik `0000` kod bilan kirish
  /// uchun `bypass_0000` secret bilan OTP ekraniga o'tkazadi.
  Future<bool> login(String phoneNumber) async {
    _setLoading(true);
    _clearError();
    _lastPhoneNumber = phoneNumber;

    final result = await _repository.login(phoneNumber, _selectedRole);

    return result.fold(
      onSuccess: (response) {
        _otpSecret = response.secret;
        _setLoading(false);
        return true;
      },
      onError: (_) {
        // Vaqtincha 0000 bilan tasdiqlash ishlashi uchun fallback secret
        _otpSecret = 'bypass_0000';
        _setLoading(false);
        return true;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // OTP tasdiqlash (2-qadam)
  // ---------------------------------------------------------------------------

  /// OTP kodni tasdiqlaydi va foydalanuvchini tizimga kiritadi.
  ///
  /// Muvaffaqiyatli bo'lsa `true` qaytaradi.
  /// Caller `/home` ga navigate qilishi kerak.
  Future<bool> confirmOtp(String otp) async {
    if (_otpSecret == null && otp != AuthRepository.defaultBypassOtp) {
      _setError('OTP secret topilmadi. Iltimos, qaytadan urinib ko\'ring.');
      return false;
    }

    _setLoading(true);
    _clearError();

    final result = await _repository.confirmOtp(
      _otpSecret ?? 'bypass_0000',
      otp,
      phoneNumber: _lastPhoneNumber ?? '',
      role: _selectedRole,
    );

    return result.fold(
      onSuccess: (user) {
        _currentUser = user;
        _otpSecret = null;
        _setLoading(false);
        return true;
      },
      onError: (failure) {
        _setError(failure.message);
        _setLoading(false);
        return false;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // OTP qayta yuborish
  // ---------------------------------------------------------------------------

  /// OTP ni qayta yuboradi (timer tugaganda).
  Future<bool> resendOtp(String phoneNumber) async {
    _setLoading(true);
    _clearError();
    _lastPhoneNumber = phoneNumber;

    final result = await _repository.login(phoneNumber, _selectedRole);

    return result.fold(
      onSuccess: (response) {
        _otpSecret = response.secret;
        _setLoading(false);
        return true;
      },
      onError: (_) {
        _otpSecret = 'bypass_0000';
        _setLoading(false);
        return true;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Ro'yxatdan o'tish
  // ---------------------------------------------------------------------------

  /// Yangi hisob yaratadi.
  ///
  /// Muvaffaqiyatli bo'lsa `true` qaytaradi.
  /// Caller login ekraniga navigate qilishi kerak.
  Future<bool> signup(
    String phoneNumber,
    String password,
    String passwordConfirm,
  ) async {
    _setLoading(true);
    _clearError();

    final result =
        await _repository.signup(phoneNumber, password, passwordConfirm);

    return result.fold(
      onSuccess: (_) {
        _setLoading(false);
        return true;
      },
      onError: (failure) {
        _setError(failure.message);
        _setLoading(false);
        return false;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Auto login (splash ekranda)
  // ---------------------------------------------------------------------------

  /// Token bormi tekshiradi, agar bor bo'lsa profil oladi.
  ///
  /// `/splash` ekranda chaqiriladi.
  /// `true` — /home ga o'tish, `false` — /role-selection ga o'tish.
  Future<bool> tryAutoLogin() async {
    if (!_repository.isLoggedIn) {
      // Avval cache'dan tekshir
      final stored = await _repository.getStoredUser();
      if (stored == null) return false;
    }

    _setLoading(true);

    final result = await _repository.getMe();

    return result.fold(
      onSuccess: (user) {
        _currentUser = user;
        _setLoading(false);
        return true;
      },
      onError: (_) {
        _setLoading(false);
        return false;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tizimdan chiqish
  // ---------------------------------------------------------------------------

  /// Foydalanuvchini tizimdan chiqaradi.
  Future<void> logout() async {
    await _repository.logout();
    _currentUser = null;
    _activeUiRole = null;
    _otpSecret = null;
    _clearError();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Profil yangilash
  // ---------------------------------------------------------------------------

  /// Lokal profil ma'lumotlarini yangilaydi.
  void updateProfile({
    String? firstName,
    String? lastName,
    String? profilePicture,
  }) {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      firstName: firstName,
      lastName: lastName,
      profilePicture: profilePicture,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Telegram login
  // ---------------------------------------------------------------------------

  /// Telegram login sessiyasini boshlaydi.
  ///
  /// [phoneNumber] — `+998XXXXXXXXX` formatida.
  /// Muvaffaqiyatli bo'lsa [TgLoginStartResponse] qaytaradi (deep link ichida).
  Future<TgLoginStartResponse?> startTgLogin(String phoneNumber) async {
    _tgErrorMessage = null;
    _lastPhoneNumber = phoneNumber;
    _setLoading(true);

    final result = await _tgRepository.start(phoneNumber, _selectedRole);

    return result.fold(
      onSuccess: (response) {
        _tgSession = response;
        _setLoading(false);
        return response;
      },
      onError: (failure) {
        _tgErrorMessage = failure.message;
        _setLoading(false);
        return null;
      },
    );
  }

  /// Polling boshlash — har [AppConstants.tgLoginPollInterval] da status tekshiradi.
  ///
  /// Confirmed bo'lsa [onConfirmed] callback chaqiriladi.
  /// Timeout/expired/rejected yoki ketma-ket server xatosi bo'lsa [onFailed] chaqiriladi.
  void startTgPolling({
    required void Function(UserModel user) onConfirmed,
    required void Function(String reason) onFailed,
  }) {
    if (_tgSession == null) return;
    if (_tgPolling) return;

    _tgPolling = true;
    _tgConsecutiveErrors = 0;
    _tgPollStartedAt = DateTime.now();
    notifyListeners();

    _tgPollTimer = Timer.periodic(
      AppConstants.tgLoginPollInterval,
      (timer) async {
        // Timeout tekshirish
        final elapsed = DateTime.now().difference(_tgPollStartedAt!);
        if (elapsed > AppConstants.tgLoginPollTimeout) {
          timer.cancel();
          _tgPolling = false;
          notifyListeners();
          onFailed('Vaqt tugadi. Iltimos, qayta urinib ko\'ring.');
          return;
        }

        if (_tgSession == null) {
          timer.cancel();
          _tgPolling = false;
          notifyListeners();
          return;
        }

        final result = await _tgRepository.pollStatus(_tgSession!.secret);

        await result.fold(
          onSuccess: (status) async {
            _tgConsecutiveErrors = 0;
            _tgStatus = status;

            if (status.isConfirmed) {
              timer.cancel();
              _tgPolling = false;
              final user = await _tgRepository.persistFromStatus(
                status,
                fallbackPhone: _tgSession?.phoneNumber ?? _lastPhoneNumber,
                fallbackRole: _selectedRole,
              );
              if (user != null) {
                _currentUser = user;
                _tgSession = null;
                notifyListeners();
                onConfirmed(user);
              } else {
                notifyListeners();
                onFailed('Foydalanuvchi ma\'lumotlari olinmadi.');
              }
            } else if (status.isFinished) {
              timer.cancel();
              _tgPolling = false;
              notifyListeners();
              onFailed(status.message ?? 'Tasdiqlash amalga oshmadi.');
            } else {
              notifyListeners();
            }
            return null;
          },
          onError: (failure) {
            _tgConsecutiveErrors++;
            // Agar server ketma-ket 3 marta xato bersa (masalan 500 Server Error),
            // foydalanuvchini "Telegram'da kutilmoqda" ekranida qotirib qo'ymasdan to'xtatamiz.
            if (_tgConsecutiveErrors >= 3) {
              timer.cancel();
              _tgPolling = false;
              notifyListeners();
              onFailed(
                'Telegram xizmatida vaqtinchalik xatolik (${failure.message}). '
                'SMS kod sifatida 0000 kiritib kirishingiz mumkin.',
              );
            }
            return null;
          },
        );
      },
    );
  }

  /// Telegram pollingni to'xtatadi.
  void stopTgPolling() {
    _tgPollTimer?.cancel();
    _tgPollTimer = null;
    _tgPolling = false;
    _tgConsecutiveErrors = 0;
    notifyListeners();
  }

  /// Manual status check — foydalanuvchi "Tekshirish" tugmasini bosganda
  /// yoki Telegramdan ilovaga qaytganda.
  ///
  /// Confirmed bo'lsa polling to'xtatiladi va [onConfirmed] chaqiriladi.
  Future<void> checkTgStatusOnce({
    required void Function(UserModel user) onConfirmed,
    required void Function(String reason) onFailed,
  }) async {
    if (_tgSession == null) {
      _tgPolling = false;
      notifyListeners();
      onFailed('Sessiya topilmadi.');
      return;
    }

    final result = await _tgRepository.pollStatus(_tgSession!.secret);

    await result.fold(
      onSuccess: (status) async {
        _tgStatus = status;

        if (status.isConfirmed) {
          _tgPollTimer?.cancel();
          _tgPolling = false;
          final user = await _tgRepository.persistFromStatus(
            status,
            fallbackPhone: _tgSession?.phoneNumber ?? _lastPhoneNumber,
            fallbackRole: _selectedRole,
          );
          if (user != null) {
            _currentUser = user;
            _tgSession = null;
            notifyListeners();
            onConfirmed(user);
          } else {
            notifyListeners();
            onFailed('Foydalanuvchi ma\'lumotlari olinmadi.');
          }
        } else if (status.isFinished) {
          _tgPollTimer?.cancel();
          _tgPolling = false;
          notifyListeners();
          onFailed(status.message ?? 'Tasdiqlash amalga oshmadi.');
        } else {
          notifyListeners();
          onFailed('Hali tasdiqlanmadi. Botda kontaktni ulashing yoki 0000 kod bilan kiring.');
        }
        return null;
      },
      onError: (failure) {
        _tgPollTimer?.cancel();
        _tgPolling = false;
        notifyListeners();
        onFailed(
          'Telegram server xatosi: ${failure.message}. '
          'Vaqtincha 0000 kod orqali kirishingiz mumkin.',
        );
        return null;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Yordamchi metodlar
  // ---------------------------------------------------------------------------

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  @override
  void dispose() {
    _tgPollTimer?.cancel();
    super.dispose();
  }
}
