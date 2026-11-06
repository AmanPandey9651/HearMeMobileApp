import '../common/legal_policy_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../listener/listener_verification_pending_screen.dart';

class ListenerRegisterScreen extends StatefulWidget {
  const ListenerRegisterScreen({super.key});

  @override
  State<ListenerRegisterScreen> createState() => _ListenerRegisterScreenState();
}

class _ListenerRegisterScreenState extends State<ListenerRegisterScreen> {
  bool _agreedToPolicy = false;
  // Account Information Controllers
  final first = TextEditingController();
  final last = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final gender = TextEditingController(text: 'Prefer not to say');

  // Address & Verification Controllers
  String selectedDialCode = '+91';
  String selectedCountryFlag = '🇮🇳';
  final country = TextEditingController(text: 'India');
  final state = TextEditingController(text: 'Maharashtra');
  final fullAddress = TextEditingController();
  String selectedIdType = 'AADHAAR'; // 'AADHAAR', 'PAN', 'PASSPORT', 'NATIONAL_ID', 'DRIVING_LICENSE'
  final idNumber = TextEditingController();

  // Verification state
  bool verifyingId = false;
  bool idVerified = false;
  String? idMasked;
  String? idVerificationMethod;
  String? idVerificationMessage;
  String? idVerificationError;

  // Listener Profile Controllers
  final title = TextEditingController(text: 'Empathetic Listener');
  final bio = TextEditingController();
  final languages = TextEditingController(text: 'Hindi, English');
  final availability = TextEditingController(text: 'Evenings, Weekends, Flexible');

  // Rates (Defaults)
  final audio = TextEditingController(text: '10');
  final video = TextEditingController(text: '15');
  final chat = TextEditingController(text: '5');

  bool _obscurePassword = true;
  bool busy = false;
  Map<String, dynamic>? limits;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  static const List<CountryOption> countryOptions = [
    CountryOption('India', '🇮🇳', '+91'),
    CountryOption('United States', '🇺🇸', '+1'),
    CountryOption('United Kingdom', '🇬🇧', '+44'),
    CountryOption('Canada', '🇨🇦', '+1'),
    CountryOption('Australia', '🇦🇺', '+61'),
    CountryOption('United Arab Emirates', '🇦🇪', '+971'),
    CountryOption('Germany', '🇩🇪', '+49'),
    CountryOption('France', '🇫🇷', '+33'),
    CountryOption('Singapore', '🇸🇬', '+65'),
    CountryOption('Saudi Arabia', '🇸🇦', '+966'),
    CountryOption('New Zealand', '🇳🇿', '+64'),
    CountryOption('Other Country', '🌐', '+1'),
  ];

  static const List<String> indianStates = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram',
    'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
    'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Delhi NCR', 'Jammu and Kashmir', 'Ladakh', 'Chandigarh', 'Puducherry'
  ];

  static const List<String> genderOptions = [
    'Female', 'Male', 'Non-Binary', 'Prefer not to say'
  ];

  static const List<String> professionalTitles = [
    'Empathetic Listener', 'Compassionate Peer', 'Mindful Friend',
    'Life Guidance Listener', 'Relationship Advisor', 'Career & Stress Support'
  ];

  static const List<String> availabilityOptions = [
    'Evenings, Weekends, Flexible', 'Full-time (9 AM - 9 PM)', 'Late Night Owls (9 PM - 2 AM)',
    'Mornings & Afternoons', 'Weekends Only', 'Flexible on Demand'
  ];

  @override
  void initState() {
    super.initState();
    bio.addListener(() {
      if (mounted) setState(() {});
    });
    _loadLimits();
  }

  Future<void> _loadLimits() async {
    try {
      final v = await context.read<AppController>().api.rateLimits();
      if (mounted) setState(() => limits = v);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [first, last, email, phone, password, gender, country, state, fullAddress, idNumber, title, bio, languages, availability, audio, video, chat]) {
      c.dispose();
    }
    super.dispose();
  }

  String _getIdLabel() {
    switch (selectedIdType) {
      case 'AADHAAR':
        return '12-digit Aadhaar Number *';
      case 'PAN':
        return '10-character PAN Number *';
      case 'PASSPORT':
        return 'Passport Number (ICAO 9303) *';
      case 'NATIONAL_ID':
        return 'National ID / Civil Registry Number *';
      case 'DRIVING_LICENSE':
        return "Driver's License Number *";
      default:
        return 'Government ID Number *';
    }
  }

  String _getIdHint() {
    switch (selectedIdType) {
      case 'AADHAAR':
        return 'e.g. 5489 1234 5678';
      case 'PAN':
        return 'e.g. ABCDE1234F';
      case 'PASSPORT':
        return 'e.g. A1234567 or N12345678';
      case 'NATIONAL_ID':
        return country.text == 'United Arab Emirates'
            ? 'e.g. 784-1990-1234567-1'
            : 'e.g. SSN / National Card / BRP';
      case 'DRIVING_LICENSE':
        return 'e.g. DL-1420110012345 or D12345678';
      default:
        return 'Enter ID number';
    }
  }

  IconData _getIdIcon() {
    switch (selectedIdType) {
      case 'AADHAAR':
        return Icons.fingerprint_rounded;
      case 'PAN':
        return Icons.credit_card_rounded;
      case 'PASSPORT':
        return Icons.public_rounded;
      case 'NATIONAL_ID':
        return Icons.badge_outlined;
      case 'DRIVING_LICENSE':
        return Icons.drive_eta_rounded;
      default:
        return Icons.badge_outlined;
    }
  }

  Future<void> _pickCountry() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Country & Dial Code',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textDark),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: borderWarm),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: countryOptions.length,
                  itemBuilder: (ctx, i) {
                    final opt = countryOptions[i];
                    final isSel = opt.name == country.text;
                    return ListTile(
                      leading: Text(opt.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(
                        opt.name,
                        style: TextStyle(
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          color: isSel ? primaryOrange : textDark,
                        ),
                      ),
                      trailing: Text(
                        opt.dialCode,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSel ? primaryOrange : textMuted,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          country.text = opt.name;
                          selectedDialCode = opt.dialCode;
                          selectedCountryFlag = opt.flag;
                          idVerified = false;
                          idVerificationError = null;
                          if (opt.name == 'India') {
                            if (selectedIdType != 'AADHAAR' && selectedIdType != 'PAN') {
                              selectedIdType = 'AADHAAR';
                            }
                            if (state.text.isEmpty) {
                              state.text = 'Maharashtra';
                            }
                          } else {
                            if (selectedIdType == 'AADHAAR' || selectedIdType == 'PAN') {
                              selectedIdType = 'PASSPORT';
                            }
                            if (state.text == 'Maharashtra') {
                              state.text = '';
                            }
                          }
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verifyGovtId() async {
    final rawId = idNumber.text.trim();
    if (rawId.isEmpty) {
      String expected;
      if (selectedIdType == 'AADHAAR') {
        expected = '12-digit Aadhaar';
      } else if (selectedIdType == 'PAN') {
        expected = '10-character PAN';
      } else if (selectedIdType == 'PASSPORT') {
        expected = '6-12 character Passport';
      } else if (selectedIdType == 'NATIONAL_ID') {
        expected = 'National ID / Civil Registry';
      } else {
        expected = "Driver's License";
      }
      setState(() {
        idVerificationError = 'Please enter your $expected number first.';
        idVerified = false;
      });
      return;
    }

    setState(() {
      verifyingId = true;
      idVerificationError = null;
    });

    try {
      final fullName = '${first.text.trim()} ${last.text.trim()}'.trim();
      final res = await context.read<AppController>().api.verifyGovtId(
        idType: selectedIdType,
        idNumber: rawId,
        name: fullName.isNotEmpty ? fullName : null,
        state: state.text.trim().isNotEmpty ? state.text.trim() : null,
        country: country.text.trim().isNotEmpty ? country.text.trim() : null,
      );

      if (mounted) {
        setState(() {
          idVerified = res['verified'] == true;
          idMasked = res['maskedId'] as String?;
          idVerificationMethod = res['verificationMethod'] as String?;
          idVerificationMessage = res['message'] as String? ?? 'Verified successfully with government registry.';
          idVerificationError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll('Exception: ', '').replaceAll('BadRequestException: ', '');
        setState(() {
          idVerified = false;
          idVerificationError = err;
        });
      }
    } finally {
      if (mounted) setState(() => verifyingId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Join as a Listener',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textDark),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
          children: [
            // 1. Hero Showcase Banner (Warm luxury peach gradient matching Screenshot 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF2EB), Color(0xFFFFE8DD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFFFCDFD5), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [primaryOrange, secondaryOrange],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryOrange.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Support Callers & Earn',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Set your rates & listen on your schedule.',
                              style: TextStyle(fontSize: 12, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                      const _HeartBlushSticker(size: 46),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _BenefitBadge(icon: Icons.currency_rupee_rounded, text: 'Keep 100% Tips'),
                      _BenefitBadge(icon: Icons.shield_rounded, text: 'Anonymous Calls'),
                      _BenefitBadge(icon: Icons.schedule_rounded, text: 'Flexible Hours'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Section 1: Account Information Card (Matching Screenshot 2)
            _SectionContainer(
              title: 'Account Information',
              subtitle: 'Create your account to get started.',
              icon: Icons.person_outline_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: first,
                        style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: _inputDeco(
                          label: 'First name *',
                          prefix: const Icon(Icons.person_outline_rounded, color: primaryOrange, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: last,
                        style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: _inputDeco(
                          label: 'Last name *',
                          prefix: const Icon(Icons.person_outline_rounded, color: primaryOrange, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: _inputDeco(
                    label: 'Email address *',
                    prefix: const Icon(Icons.mail_outline_rounded, color: primaryOrange, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    InkWell(
                      onTap: _pickCountry,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBF7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderWarm),
                        ),
                        child: Row(
                          children: [
                            Text(selectedCountryFlag, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              selectedDialCode,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: _inputDeco(
                          label: 'Phone number *',
                          hint: selectedDialCode == '+91' ? '98765 43210' : 'e.g. 555-0199 or 50 123 4567',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: _inputDeco(
                    label: 'Password (min 8 characters) *',
                    prefix: const Icon(Icons.lock_outline_rounded, color: primaryOrange, size: 20),
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                        color: textMuted,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _pickOption(
                    title: 'Select Gender',
                    options: genderOptions,
                    selected: gender.text,
                    onSelected: (v) => setState(() => gender.text = v),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: IgnorePointer(
                    child: TextField(
                      controller: gender,
                      style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                      decoration: _inputDeco(
                        label: 'Gender',
                        prefix: const Icon(Icons.transgender_rounded, color: primaryOrange, size: 20),
                        suffix: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 3. Section 2: Address & Government ID Verification (Requirement 2)
            _SectionContainer(
              title: 'Address & Govt Verification',
              subtitle: country.text == 'India'
                  ? 'Mandatory verification under Government of India guidelines.'
                  : 'Official identity verification under ${country.text} national standards.',
              icon: Icons.verified_user_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickCountry,
                        borderRadius: BorderRadius.circular(14),
                        child: IgnorePointer(
                          child: TextField(
                            controller: country,
                            style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                            decoration: _inputDeco(
                              label: 'Country *',
                              prefix: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                child: Text(selectedCountryFlag, style: const TextStyle(fontSize: 18)),
                              ),
                              suffix: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: country.text == 'India'
                          ? InkWell(
                              onTap: () => _pickOption(
                                title: 'Select State / UT',
                                options: indianStates,
                                selected: state.text,
                                onSelected: (v) => setState(() => state.text = v),
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: IgnorePointer(
                                child: TextField(
                                  controller: state,
                                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                                  decoration: _inputDeco(
                                    label: 'State *',
                                    prefix: const Icon(Icons.map_outlined, color: primaryOrange, size: 19),
                                    suffix: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 20),
                                  ),
                                ),
                              ),
                            )
                          : TextField(
                              controller: state,
                              style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                              decoration: _inputDeco(
                                label: 'State / Province *',
                                hint: 'e.g. California, Dubai, Ontario',
                                prefix: const Icon(Icons.map_outlined, color: primaryOrange, size: 19),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fullAddress,
                  minLines: 2,
                  maxLines: 3,
                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w500, fontSize: 13.5),
                  decoration: _inputDeco(
                    label: 'Full residential address *',
                    hint: country.text == 'India'
                        ? 'House/Flat No., Street, Landmark, City & PIN code'
                        : 'Street address, Apt/Suite, City, Postal / ZIP code',
                    prefix: const Icon(Icons.location_on_outlined, color: primaryOrange, size: 20),
                  ),
                ),
                const SizedBox(height: 16),

                // ID Type Segmented Pill
                Text(
                  country.text == 'India'
                      ? 'Select Government ID for Verification *'
                      : 'Select ${country.text} Identity Document *',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textDark),
                ),
                const SizedBox(height: 8),
                if (country.text == 'India')
                  Row(
                    children: [
                      Expanded(
                        child: _IdTypePill(
                          label: 'Aadhaar (UIDAI)',
                          icon: Icons.fingerprint_rounded,
                          selected: selectedIdType == 'AADHAAR',
                          onTap: () {
                            if (selectedIdType != 'AADHAAR') {
                              setState(() {
                                selectedIdType = 'AADHAAR';
                                idVerified = false;
                                idVerificationError = null;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _IdTypePill(
                          label: 'PAN (IT Dept)',
                          icon: Icons.credit_card_rounded,
                          selected: selectedIdType == 'PAN',
                          onTap: () {
                            if (selectedIdType != 'PAN') {
                              setState(() {
                                selectedIdType = 'PAN';
                                idVerified = false;
                                idVerificationError = null;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _IdTypePill(
                              label: 'Passport (ICAO)',
                              icon: Icons.public_rounded,
                              selected: selectedIdType == 'PASSPORT',
                              onTap: () {
                                if (selectedIdType != 'PASSPORT') {
                                  setState(() {
                                    selectedIdType = 'PASSPORT';
                                    idVerified = false;
                                    idVerificationError = null;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _IdTypePill(
                              label: 'National ID',
                              icon: Icons.badge_outlined,
                              selected: selectedIdType == 'NATIONAL_ID',
                              onTap: () {
                                if (selectedIdType != 'NATIONAL_ID') {
                                  setState(() {
                                    selectedIdType = 'NATIONAL_ID';
                                    idVerified = false;
                                    idVerificationError = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _IdTypePill(
                        label: "Driver's License (Transport Authority)",
                        icon: Icons.drive_eta_rounded,
                        selected: selectedIdType == 'DRIVING_LICENSE',
                        onTap: () {
                          if (selectedIdType != 'DRIVING_LICENSE') {
                            setState(() {
                              selectedIdType = 'DRIVING_LICENSE';
                              idVerified = false;
                              idVerificationError = null;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 12),

                // ID Number input with inline Verify Button
                TextField(
                  controller: idNumber,
                  keyboardType: selectedIdType == 'AADHAAR' ? TextInputType.number : TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 1.1),
                  onChanged: (_) {
                    if (idVerified) {
                      setState(() => idVerified = false);
                    }
                  },
                  decoration: _inputDeco(
                    label: _getIdLabel(),
                    hint: _getIdHint(),
                    prefix: Icon(
                      _getIdIcon(),
                      color: primaryOrange,
                      size: 20,
                    ),
                    suffix: idVerified
                        ? const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),

                // Verification trigger & feedback
                if (idVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Verified by ${country.text} Authority ($selectedIdType)',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                              ),
                              if (idMasked != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Masked ID: $idMasked • ${idVerificationMethod ?? "Government Registry"}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (idVerificationError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              idVerificationError!,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: verifyingId ? null : _verifyGovtId,
                    icon: verifyingId
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: primaryOrange, strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_rounded, size: 17, color: primaryOrange),
                    label: Text(
                      verifyingId ? 'Verifying with Govt Registry…' : 'Verify $selectedIdType',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: primaryOrange, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryOrange, width: 1.3),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 18),

            // 4. Section 3: Listener Profile (Matching Screenshot 2)
            _SectionContainer(
              title: 'Listener Profile',
              subtitle: 'Help callers know you better.',
              icon: Icons.business_center_outlined,
              children: [
                InkWell(
                  onTap: () => _pickOption(
                    title: 'Select Professional Title',
                    options: professionalTitles,
                    selected: title.text,
                    onSelected: (v) => setState(() => title.text = v),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: IgnorePointer(
                    child: TextField(
                      controller: title,
                      style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                      decoration: _inputDeco(
                        label: 'Professional title *',
                        prefix: const Icon(Icons.work_outline_rounded, color: primaryOrange, size: 20),
                        suffix: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    TextField(
                      controller: bio,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 5,
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                      style: const TextStyle(color: textDark, fontSize: 13.5),
                      decoration: _inputDeco(
                        label: 'Bio & Introduction *',
                        hint: 'Tell us about yourself, your listening style, and what makes you a great listener...',
                        prefix: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.description_outlined, color: primaryOrange, size: 20),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 8),
                      child: Text(
                        '${bio.text.length}/500',
                        style: const TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: languages,
                  style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: _inputDeco(
                    label: 'Languages spoken (comma-separated) *',
                    hint: 'Hindi, English',
                    prefix: const Icon(Icons.language_rounded, color: primaryOrange, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _pickOption(
                    title: 'Select Availability',
                    options: availabilityOptions,
                    selected: availability.text,
                    onSelected: (v) => setState(() => availability.text = v),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: IgnorePointer(
                    child: TextField(
                      controller: availability,
                      style: const TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 14),
                      decoration: _inputDeco(
                        label: 'Availability (optional)',
                        hint: 'eg. Evenings, Weekends, Flexible',
                        prefix: const Icon(Icons.calendar_today_rounded, color: primaryOrange, size: 19),
                        suffix: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Mandatory Policy Acceptance Checkbox
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _agreedToPolicy ? const Color(0xFF10B981) : borderWarm,
                  width: _agreedToPolicy ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreedToPolicy,
                      activeColor: primaryOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onChanged: (val) {
                        setState(() => _agreedToPolicy = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      children: [
                        const Text(
                          'I have read and agree to the ',
                          style: TextStyle(fontSize: 12.5, color: textDark, height: 1.4),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalPolicyScreen(initialTab: 0))),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(fontSize: 12.5, color: primaryOrange, fontWeight: FontWeight.w800, decoration: TextDecoration.underline, height: 1.4),
                          ),
                        ),
                        const Text(
                          ' and ',
                          style: TextStyle(fontSize: 12.5, color: textDark, height: 1.4),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalPolicyScreen(initialTab: 1))),
                          child: const Text(
                            'Terms of Service',
                            style: TextStyle(fontSize: 12.5, color: primaryOrange, fontWeight: FontWeight.w800, decoration: TextDecoration.underline, height: 1.4),
                          ),
                        ),
                        const Text(
                          ', and affirm to maintain 100% confidentiality of all caller sessions.',
                          style: TextStyle(fontSize: 12.5, color: textDark, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Submit Button (Big orange gradient pill with right arrow matching Screenshot 2)
            Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: (busy || !_agreedToPolicy)
                      ? [const Color(0xFFD1D5DB), const Color(0xFF9CA3AF)]
                      : [primaryOrange, secondaryOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _agreedToPolicy ? primaryOrange.withValues(alpha: 0.35) : Colors.transparent,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: (busy || !_agreedToPolicy) ? null : _submit,
                  child: Center(
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Create My Listener Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Terms of Service Disclaimer matching Screenshot 2
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(fontSize: 12, color: textMuted),
                  children: [
                    TextSpan(text: 'By signing up, you agree to our '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static InputDecoration _inputDeco({
    required String label,
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: textMuted),
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), fontWeight: FontWeight.normal),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFFFFBF7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: borderWarm),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: borderWarm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryOrange, width: 1.4),
      ),
    );
  }

  Future<void> _pickOption({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textDark),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: borderWarm),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (ctx, i) {
                    final opt = options[i];
                    final isSel = opt == selected;
                    return ListTile(
                      title: Text(
                        opt,
                        style: TextStyle(
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          color: isSel ? primaryOrange : textDark,
                        ),
                      ),
                      trailing: isSel ? const Icon(Icons.check_rounded, color: primaryOrange) : null,
                      onTap: () {
                        onSelected(opt);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
        throw Exception('First and last name are required.');
      }
      if (!email.text.contains('@')) {
        throw Exception('Please enter a valid email address.');
      }
      if (phone.text.trim().isEmpty) {
        throw Exception('Phone number is required.');
      }
      final cleanDigits = phone.text.replaceAll(RegExp(r'\D'), '');
      if (country.text.trim() == 'India' && cleanDigits.length < 10) {
        throw Exception('Please enter a valid 10-digit mobile number.');
      } else if (cleanDigits.length < 7) {
        throw Exception('Please enter a valid phone number.');
      }
      if (password.text.length < 8) {
        throw Exception('Password must be at least 8 characters.');
      }
      if (country.text.trim().isEmpty) {
        throw Exception('Please select your country.');
      }
      if (state.text.trim().isEmpty) {
        throw Exception(country.text == 'India'
            ? 'Please select your state.'
            : 'Please enter your state / province / region.');
      }
      if (fullAddress.text.trim().isEmpty) {
        throw Exception('Full address is required.');
      }
      if (idNumber.text.trim().isEmpty) {
        throw Exception('Government ID document number is required.');
      }
      if (title.text.trim().isEmpty) {
        throw Exception('Professional title is required.');
      }
      if (bio.text.trim().isEmpty || bio.text.trim().length < 15) {
        throw Exception('A personal bio statement (minimum 15 characters) is required.');
      }

      final isIntl = country.text.trim().toLowerCase() != 'india' && country.text.trim().toLowerCase() != 'in';
      final amax = isIntl ? ((limits?['maxInternationalAudioRatePerMinute'] as num?)?.toDouble() ?? 150.0) : ((limits?['maxAudioRatePerMinute'] as num?)?.toDouble() ?? 50.0);
      final amin = isIntl ? ((limits?['minInternationalAudioRatePerMinute'] as num?)?.toDouble() ?? 20.0) : ((limits?['minAudioRatePerMinute'] as num?)?.toDouble() ?? 5.0);
      final vmax = isIntl ? ((limits?['maxInternationalVideoRatePerMinute'] as num?)?.toDouble() ?? 250.0) : ((limits?['maxVideoRatePerMinute'] as num?)?.toDouble() ?? 100.0);
      final vmin = isIntl ? ((limits?['minInternationalVideoRatePerMinute'] as num?)?.toDouble() ?? 35.0) : ((limits?['minVideoRatePerMinute'] as num?)?.toDouble() ?? 10.0);
      final cmax = isIntl ? ((limits?['maxInternationalChatRatePerMinute'] as num?)?.toDouble() ?? 80.0) : ((limits?['maxChatRatePerMinute'] as num?)?.toDouble() ?? 30.0);
      final cmin = isIntl ? ((limits?['minInternationalChatRatePerMinute'] as num?)?.toDouble() ?? 10.0) : ((limits?['minChatRatePerMinute'] as num?)?.toDouble() ?? 2.0);

      double a = double.tryParse(audio.text) ?? (isIntl ? amin : 10.0);
      double v = double.tryParse(video.text) ?? (isIntl ? vmin : 15.0);
      double c = double.tryParse(chat.text) ?? (isIntl ? cmin : 5.0);

      if (a < amin) a = amin;
      if (a > amax) a = amax;
      if (v < vmin) v = vmin;
      if (v > vmax) v = vmax;
      if (c < cmin) c = cmin;
      if (c > cmax) c = cmax;

      final fullPhoneNumber = '$selectedDialCode${phone.text.trim().replaceAll(RegExp(r'^\+'), '')}';

      await context.read<AppController>().registerListener({
        'email': email.text.trim(),
        'password': password.text,
        'firstName': first.text.trim(),
        'lastName': last.text.trim(),
        'phoneNumber': fullPhoneNumber,
        'mobileNumber': fullPhoneNumber,
        'countryCode': selectedDialCode,
        'gender': gender.text.trim(),
        'hobbies': 'Listening, Reading, Mindful Conversation',
        'country': country.text.trim(),
        'state': state.text.trim(),
        'fullAddress': fullAddress.text.trim(),
        'idType': selectedIdType,
        'idNumber': idNumber.text.trim(),
        'idVerified': idVerified,
        'languages': languages.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'professionalTitle': title.text.trim(),
        'bio': bio.text.trim().isEmpty ? 'Compassionate listener ready to offer a supportive, non-judgmental ear.' : bio.text.trim(),
        'audioRatePerMinute': a,
        'videoRatePerMinute': v,
        'chatRatePerMinute': c,
        'timezone': 'Asia/Kolkata',
        'role': 'EXPERT',
      });

      // Navigate directly to the verification pending screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ListenerVerificationPendingScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _SectionContainer extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SectionContainer({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.borderWarm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECE5),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.primaryOrange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _IdTypePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _IdTypePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF2EB) : const Color(0xFFFFFBF7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primaryOrange : AppTheme.borderWarm,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppTheme.primaryOrange : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppTheme.primaryOrange : AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCDFD5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryOrange),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textDark),
          ),
        ],
      ),
    );
  }
}

class _HeartBlushSticker extends StatelessWidget {
  final double size;
  const _HeartBlushSticker({this.size = 50});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 14,
      height: size + 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + 8,
            height: size + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFAB91).withValues(alpha: 0.38),
                  const Color(0xFFFFCCBC).withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.16,
            child: Icon(
              Icons.favorite_rounded,
              color: const Color(0xFFFF8A65).withValues(alpha: 0.85),
              size: size * 0.65,
            ),
          ),
          Positioned(
            top: 2,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2.8,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
                Transform.rotate(
                  angle: 0.38,
                  child: Container(
                    width: 2.8,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CountryOption {
  final String name;
  final String flag;
  final String dialCode;
  const CountryOption(this.name, this.flag, this.dialCode);
}
