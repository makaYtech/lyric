import 'package:flutter/material.dart';
import '../core/cache/cache_service.dart';
import '../core/theme/theme_controller.dart';
import '../models/academic_year.dart';
import '../models/student_profile.dart';
import '../models/subject_grade.dart';
import '../repositories/academic_years_repository.dart';
import '../repositories/grades_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../widgets/global_refresh_bar.dart';
import 'grades_view.dart';
import 'profile_view.dart';
import 'settings_screen.dart';

/// Владеет данными и состоянием ОБЕИХ вкладок — это нужно, чтобы кнопка
/// "Обновить всё" могла дёрнуть оба репозитория разом, а не только тот,
/// что видно на экране прямо сейчас. Сами экраны (ProfileView/GradesView)
/// не знают про сеть и кэш вообще — только отображают то, что им передали.
class HomeScreen extends StatefulWidget {
  final EposTokens tokens;
  final ThemeController themeController;

  const HomeScreen({
    super.key,
    required this.tokens,
    required this.themeController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _profileRepository = ProfileRepository();
  final _gradesRepository = GradesRepository();
  final _yearsRepository = AcademicYearsRepository();
  final _cache = CacheService();

  static const _selectedYearKey = 'selected_academic_year_id';
  static const _fallbackYearId = 14;

  int _tabIndex = 0;

  StudentProfile? _profile;
  DateTime? _profileUpdated;
  bool _profileLoading = false;
  String? _profileError;

  List<SubjectGrade>? _grades;
  DateTime? _gradesUpdated;
  bool _gradesLoading = false;
  String? _gradesError;

  List<AcademicYear>? _years;
  int _selectedYearId = _fallbackYearId;

  @override
  void initState() {
    super.initState();
    _loadCachedAll();
  }

  Future<void> _loadCachedAll() async {
    final profile = await _profileRepository.loadCached();
    final profileUpdated = await _profileRepository.lastUpdated();
    final years = await _yearsRepository.loadCached();
    final savedYearId = await _cache.loadInt(_selectedYearKey);
    final yearId = savedYearId ?? _currentYearIdFrom(years) ?? _fallbackYearId;
    final grades = await _gradesRepository.loadCached(yearId);
    final gradesUpdated = await _gradesRepository.lastUpdated(yearId);

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _profileUpdated = profileUpdated;
      _years = years;
      _selectedYearId = yearId;
      _grades = grades;
      _gradesUpdated = gradesUpdated;
    });
  }

  int? _currentYearIdFrom(List<AcademicYear>? years) {
    if (years == null) return null;
    for (final y in years) {
      if (y.currentYear) return y.id;
    }
    return null;
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await _profileRepository.refresh(widget.tokens);
      final updated = await _profileRepository.lastUpdated();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileUpdated = updated;
      });
    } catch (e) {
      if (mounted) setState(() => _profileError = 'Не удалось обновить: $e');
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _refreshGrades() async {
    setState(() {
      _gradesLoading = true;
      _gradesError = null;
    });
    try {
      // Список годов тоже обновляем тут же — он нужен для дропдауна
      // и меняется редко, лишний запрос не проблема.
      final years = await _yearsRepository.refresh(widget.tokens);
      final grades = await _gradesRepository.refresh(
        widget.tokens,
        _selectedYearId,
      );
      final updated = await _gradesRepository.lastUpdated(_selectedYearId);
      if (!mounted) return;
      setState(() {
        _years = years;
        _grades = grades;
        _gradesUpdated = updated;
      });
    } catch (e) {
      if (mounted) setState(() => _gradesError = 'Не удалось обновить: $e');
    } finally {
      if (mounted) setState(() => _gradesLoading = false);
    }
  }

  Future<void> _refreshAll() =>
      Future.wait([_refreshProfile(), _refreshGrades()]);

  Future<void> _refreshCurrentTab() =>
      _tabIndex == 0 ? _refreshProfile() : _refreshGrades();

  Future<void> _onYearChanged(int yearId) async {
    setState(() => _selectedYearId = yearId);
    await _cache.saveInt(_selectedYearKey, yearId);
    final cached = await _gradesRepository.loadCached(yearId);
    final updated = await _gradesRepository.lastUpdated(yearId);
    if (!mounted) return;
    setState(() {
      _grades = cached;
      _gradesUpdated = updated;
    });
  }

  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    if (i == _tabIndex) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProfileTab = _tabIndex == 0;

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            isProfileTab ? 'Профиль' : 'Оценки',
            key: ValueKey(_tabIndex),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SettingsScreen(themeController: widget.themeController),
              ),
            ),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _tabIndex = i),
        children: [
          ProfileView(
            profile: _profile,
            isLoading: _profileLoading,
            error: _profileError,
          ),
          GradesView(
            grades: _grades,
            isLoading: _gradesLoading,
            error: _gradesError,
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlobalRefreshBar(
            lastUpdated: isProfileTab ? _profileUpdated : _gradesUpdated,
            isLoading: isProfileTab ? _profileLoading : _gradesLoading,
            onRefreshAll: _refreshAll,
            onRefreshCurrent: _refreshCurrentTab,
            currentTabLabel: isProfileTab ? 'Профиль' : 'Оценки',
          ),
          NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: _onTabSelected,   // ← было setState
            destinations: const [
              NavigationDestination(icon: Icon(Icons.person), label: 'Профиль'),
              NavigationDestination(icon: Icon(Icons.grade), label: 'Оценки'),
            ],
          ),
        ],
      ),
    );
  }
}
