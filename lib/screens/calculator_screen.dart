import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/storage.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/cpf_allocation.dart';
import '../utils/projection.dart';
import '../widgets/projection_chart.dart';

/// Keys the inputs are stored under. Named rather than positional so a field
/// added later cannot shift what an older save meant.
const _kGross = 'gross';
const _kEmployeeCpf = 'employeeCpf';
const _kCeiling = 'ceiling';
const _kMonthlyInvestment = 'monthlyInvestment';
const _kExpenses = 'expenses';
const _kStartInvestments = 'startInvestments';
const _kStartOa = 'startOa';
const _kStartSa = 'startSa';
const _kStartMa = 'startMa';
const _kAge = 'age';
const _kOaPercent = 'oaPercent';
const _kSaPercent = 'saPercent';
const _kMaPercent = 'maPercent';
const _kInvestReturn = 'investReturn';
const _kOaReturn = 'oaReturn';
const _kSaReturn = 'saReturn';
const _kMaReturn = 'maReturn';
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
    _kCeiling: 0,
    _kMonthlyInvestment: 0,
    _kExpenses: 0,
    _kStartInvestments: 0,
    _kStartOa: 0,
    _kStartSa: 0,
    _kStartMa: 0,
    _kAge: 0,
    _kOaPercent: 23,
    _kSaPercent: 6,
    _kMaPercent: 8,
    _kInvestReturn: 7,
    _kOaReturn: 2.5,
    _kSaReturn: 4,
    _kMaReturn: 4,
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
      // Zero means "no ceiling", which is what an empty field should mean —
      // not a ceiling of nothing, which would stop CPF entirely.
      cpfSalaryCeiling: ceiling > 0 ? ceiling : null,
      monthlyInvestment: _value(_kMonthlyInvestment),
      monthlyExpenses: _value(_kExpenses),
      startingInvestments: _value(_kStartInvestments),
      startingOa: _value(_kStartOa),
      startingSa: _value(_kStartSa),
      startingMa: _value(_kStartMa),
      currentAge: _value(_kAge).round().clamp(0, 100),
      oaPercent: _value(_kOaPercent),
      saPercent: _value(_kSaPercent),
      maPercent: _value(_kMaPercent),
      investmentReturnPercent: _value(_kInvestReturn),
      oaReturnPercent: _value(_kOaReturn),
      saReturnPercent: _value(_kSaReturn),
      maReturnPercent: _value(_kMaReturn),
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
    final byAge = input.currentAge > 0;
    final share = input.allocationAt(0);
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
            // Each band on the chart above, named and valued. Swatched so a
            // row can be matched to its band without counting upwards.
            _row(
              'Investments',
              formatValue(summary.invested, widget.currency),
              swatch: c.pots[3],
            ),
            _row(
              'MediSave',
              formatValue(summary.ma, widget.currency),
              swatch: c.pots[2],
            ),
            _row(
              'Special Account',
              formatValue(summary.sa, widget.currency),
              swatch: c.pots[1],
            ),
            _row(
              'Ordinary Account',
              formatValue(summary.oa, widget.currency),
              swatch: c.pots[0],
            ),
            _row('CPF together', formatValue(summary.cpf, widget.currency)),
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
          _card('CPF — how it is split', [
            _field(
              _kAge,
              'Your age (blank to set the shares yourself)',
              hint: 'e.g. 30',
            ),
            const SizedBox(height: 6),
            if (byAge) ...[
              _row('Band', cpfBandLabel(input.currentAge)),
              _row('Ordinary', '${_trim(share.oa)}% of wage'),
              _row('Special', '${_trim(share.sa)}% of wage'),
              _row('MediSave', '${_trim(share.ma)}% of wage'),
              const SizedBox(height: 6),
              Text(
                'The split follows your age and keeps following it as the '
                'projection runs — at 34 today, a twenty-year projection '
                'spends time in three bands, and holding the first for all '
                'twenty would overstate the Ordinary Account for most of it.'
                '\n\nFigures are percentages of wage for private-sector '
                'employees above \$750 a month, effective 1 January 2026. '
                'Allocation moves; clear the age to type the shares in '
                'yourself if this table has gone stale.',
                style: TextStyle(
                  color: c.textFaint,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              if (input.outgrowsAllocationTable) ...[
                const SizedBox(height: 8),
                Text(
                  'This projection runs past 55, where CPF stops working the '
                  'way this models it: the Special Account closes, '
                  'contributions go to a Retirement Account up to the Full '
                  'Retirement Sum, and the total rate falls below 37%. Years '
                  'past 55 are carried on the 50-to-55 split and are an '
                  'approximation, not a projection.',
                  style: TextStyle(color: c.down, fontSize: 12.5, height: 1.4),
                ),
              ],
            ] else ...[
              _field(_kOaPercent, 'Ordinary share of wage', suffix: '%'),
              _field(_kSaPercent, 'Special share of wage', suffix: '%'),
              _field(_kMaPercent, 'MediSave share of wage', suffix: '%'),
            ],
            const SizedBox(height: 6),
            _row('Into CPF each month', '${_trim(input.cpfPercent)}% of wage'),
            // Derived rather than asked for: what lands in CPF that did not
            // come out of take-home pay is the employer's, and two inputs
            // that had to agree would be a rule to get wrong.
            _row(
              "Employer's share",
              '${_trim(input.employerShareOfWagePercent)}% of wage',
              color: input.employeeRateExceedsCpf ? c.down : null,
            ),
            if (input.employeeRateExceedsCpf) ...[
              const SizedBox(height: 6),
              Text(
                'More is coming out of your pay than reaches CPF, which '
                'cannot happen — the shares above and your contribution rate '
                'are probably from different age bands.',
                style: TextStyle(color: c.down, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'The three accounts are kept apart because they do not pay the '
              'same: 2.5% on Ordinary against 4% on Special and MediSave, '
              'with an extra 1% on the first tranche. Averaging them into one '
              'rate hides which pot is doing the work.\n\n'
              'Shares are percentages of your wage, the form CPF publishes '
              'its allocation tables in, so a rate looked up there goes in as '
              'written.\n\n'
              'The allocation table is the only CPF policy this app carries a '
              'number for, and only when you give it an age. Interest rates, '
              'your contribution rate and the wage ceiling stay yours to set: '
              'all three have moved in recent years, and a calculator quietly '
              'using a stale figure is worse than one that asks.',
              style: TextStyle(
                color: c.textFaint,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ]),
          _card('CPF — Ordinary Account', [
            _field(_kStartOa, 'Balance today'),
            _field(_kOaReturn, 'Interest rate', suffix: '%'),
          ]),
          _card('CPF — Special Account', [
            _field(_kStartSa, 'Balance today'),
            _field(_kSaReturn, 'Interest rate', suffix: '%'),
          ]),
          _card('CPF — MediSave', [
            _field(_kStartMa, 'Balance today'),
            _field(_kMaReturn, 'Interest rate', suffix: '%'),
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

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color? color,
    Color? swatch,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // The swatch carries the identity; the label beside it stays in ink
          // rather than taking the series colour.
          if (swatch != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 7),
          ],
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
