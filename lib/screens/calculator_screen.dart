import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/storage.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/projection.dart';
import '../widgets/projection_chart.dart';

/// Keys the inputs are stored under. Named rather than positional so a field
/// added later cannot shift what an older save meant.
const _kGross = 'gross';
const _kEmployeeCpf = 'employeeCpf';
const _kEmployerCpf = 'employerCpf';
const _kCeiling = 'ceiling';
const _kMonthlyInvestment = 'monthlyInvestment';
const _kExpenses = 'expenses';
const _kStartInvestments = 'startInvestments';
const _kStartCpf = 'startCpf';
const _kInvestReturn = 'investReturn';
const _kCpfReturn = 'cpfReturn';
const _kGrowth = 'growth';
const _kYears = 'years';

/// Projects savings and CPF forward, month by month.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, this.storage, this.currency = 'SGD'});

  final WatchlistStorage? storage;
  final String currency;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late final WatchlistStorage _storage = widget.storage ?? WatchlistStorage();
  final _fields = <String, TextEditingController>{};
  bool _loading = true;

  /// Defaults chosen to be conservative where a guess would flatter the
  /// result: CPF at the Ordinary Account's 2.5% rather than the 4% paid on
  /// Special and MediSave, and no pay rise at all.
  static const _defaults = <String, double>{
    _kGross: 0,
    _kEmployeeCpf: 20,
    _kEmployerCpf: 17,
    _kCeiling: 0,
    _kMonthlyInvestment: 0,
    _kExpenses: 0,
    _kStartInvestments: 0,
    _kStartCpf: 0,
    _kInvestReturn: 7,
    _kCpfReturn: 2.5,
    _kGrowth: 0,
    _kYears: 20,
  };

  @override
  void initState() {
    super.initState();
    for (final key in _defaults.keys) {
      _fields[key] = TextEditingController()
        ..addListener(() => setState(() {}));
    }
    _load();
  }

  Future<void> _load() async {
    final saved = await _storage.loadCalculatorInputs();
    if (!mounted) return;
    setState(() {
      for (final entry in _defaults.entries) {
        final value = saved[entry.key] ?? entry.value;
        _fields[entry.key]!.text = value == 0 ? '' : _trim(value);
      }
      _loading = false;
    });
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _value(String key) =>
      double.tryParse(_fields[key]!.text.trim().replaceAll(',', '')) ??
      (_fields[key]!.text.trim().isEmpty ? _defaults[key]! : 0);

  ProjectionInput get _input {
    final ceiling = _value(_kCeiling);
    return ProjectionInput(
      grossMonthlySalary: _value(_kGross),
      employeeCpfPercent: _value(_kEmployeeCpf),
      employerCpfPercent: _value(_kEmployerCpf),
      // Zero means "no ceiling", which is what an empty field should mean —
      // not a ceiling of nothing, which would stop CPF entirely.
      cpfSalaryCeiling: ceiling > 0 ? ceiling : null,
      monthlyInvestment: _value(_kMonthlyInvestment),
      monthlyExpenses: _value(_kExpenses),
      startingInvestments: _value(_kStartInvestments),
      startingCpf: _value(_kStartCpf),
      investmentReturnPercent: _value(_kInvestReturn),
      cpfReturnPercent: _value(_kCpfReturn),
      salaryGrowthPercent: _value(_kGrowth),
      years: _value(_kYears).round().clamp(0, 60),
    );
  }

  Future<void> _save() async {
    await _storage.saveCalculatorInputs({
      for (final key in _defaults.keys) key: _value(key),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calculator')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final input = _input;
    final points = project(input);
    final summary = ProjectionSummary.of(points, input);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        actions: [
          IconButton(
            onPressed: _save,
            tooltip: 'Save these inputs',
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _card('Projection', [
            ProjectionChart(points: points, currency: widget.currency),
            const SizedBox(height: 14),
            _row(
              'In ${input.years} years',
              formatValue(summary.total, widget.currency),
              bold: true,
            ),
            _row('Investments', formatValue(summary.invested, widget.currency)),
            _row('CPF', formatValue(summary.cpf, widget.currency)),
            const Divider(height: 20),
            _row(
              'Paid in',
              formatValue(summary.totalContributed, widget.currency),
            ),
            // The number the exercise is for: how much was earned rather
            // than saved.
            _row(
              'Growth',
              formatValue(summary.growth, widget.currency),
              color: c.up,
            ),
          ]),
          _card('Salary and spending', [
            _field(_kGross, 'Gross monthly salary'),
            _field(_kEmployeeCpf, 'Your CPF contribution', suffix: '%'),
            _field(_kEmployerCpf, "Employer's CPF contribution", suffix: '%'),
            _field(
              _kCeiling,
              'CPF wage ceiling (blank for none)',
              hint: 'e.g. 7400',
            ),
            _field(_kGrowth, 'Annual pay rise', suffix: '%'),
            _field(
              _kExpenses,
              'Average monthly spending',
              hint: 'rent, food, transport, insurance',
            ),
            const SizedBox(height: 6),
            // Written as the subtraction it is, rather than two totals with
            // the working left out: what is left over is the number the rest
            // of this screen spends, and it should be obvious where it came
            // from.
            _row('Take-home pay', formatValue(input.takeHome, widget.currency)),
            _row(
              'Less spending',
              formatSignedValue(-input.monthlyExpenses, widget.currency),
            ),
            _row(
              'Less investing',
              formatSignedValue(-input.monthlyInvestment, widget.currency),
            ),
            _row(
              'Left over',
              formatValue(input.remainingAfterInvesting, widget.currency),
              bold: true,
              color: input.outgoingsExceedTakeHome ? c.down : null,
            ),
            if (input.outgoingsExceedTakeHome) ...[
              const SizedBox(height: 6),
              Text(
                'Spending and investing together come to more than take-home '
                'pay covers. The projection still runs, but the money has to '
                'come from somewhere.',
                style: TextStyle(color: c.down, fontSize: 12.5, height: 1.4),
              ),
            ],
          ]),
          _card('Investing', [
            _field(_kStartInvestments, 'Invested today'),
            _field(_kMonthlyInvestment, 'Monthly investment'),
            _field(_kInvestReturn, 'Expected annual return', suffix: '%'),
          ]),
          _card('CPF', [
            _field(_kStartCpf, 'CPF balance today'),
            _field(_kCpfReturn, 'CPF interest rate', suffix: '%'),
            const SizedBox(height: 6),
            Text(
              'CPF pays 2.5% on the Ordinary Account and 4% on Special and '
              'MediSave, with an extra 1% on the first tranche. Set the blend '
              'you expect — nothing here assumes a rate, a contribution '
              'percentage or a ceiling, because all three change.',
              style: TextStyle(
                color: c.textFaint,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ]),
          _card('Horizon', [_field(_kYears, 'Years')]),
          const SizedBox(height: 8),
          Text(
            'A projection, not a forecast. It compounds monthly at a fixed '
            'rate; real returns vary, and a single average rate hides every '
            'year that does not look average.',
            style: TextStyle(color: c.textFaint, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String key, String label, {String? suffix, String? hint}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _fields[key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: tabularFigures.copyWith(color: c.text, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          isDense: true,
          labelStyle: TextStyle(color: c.textMuted, fontSize: 14),
          filled: true,
          fillColor: c.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? c.text : c.textMuted,
                fontSize: bold ? 15 : 13.5,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: tabularFigures.copyWith(
              color: color ?? c.text,
              fontSize: bold ? 17 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
