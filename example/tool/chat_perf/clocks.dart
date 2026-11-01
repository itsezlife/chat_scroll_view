/// The CPU and GPU clock state of a launch, recorded at its start and end
/// (finding 17): the fixed performance mode does not make two sessions'
/// clocks identical, so a build-time drift can be read against them. Pure
/// Dart; the shell command that produces the input is [kClocksCommand].
library;

/// Prints one `cpu <policy> <governor> <cur> <min> <max>` line per cpufreq
/// policy (kHz) and one `gpu <cur> <min> <max>` line (MHz) where the kernel
/// exposes it. Unreadable files print nothing for their field.
const kClocksCommand =
    'for p in /sys/devices/system/cpu/cpufreq/policy*; do '
    r'echo cpu ${p##*/} $(cat $p/scaling_governor) $(cat $p/scaling_cur_freq) '
    r'$(cat $p/scaling_min_freq) $(cat $p/scaling_max_freq); done 2>/dev/null; '
    r'g=/sys/kernel/gpu; [ -r $g/gpu_clock ] && echo gpu $(cat $g/gpu_clock) '
    r'$(cat $g/gpu_min_clock) $(cat $g/gpu_max_clock) 2>/dev/null';

/// [output] of [kClocksCommand] as a metadata map: `cpu` by policy (governor
/// and kHz), `gpu` in MHz. Lines it cannot read are left out; a device that
/// exposes nothing gives an empty map.
Map<String, Object?> parseClocks(String output) {
  final cpu = <String, Object?>{};
  Map<String, Object?>? gpu;
  for (final line in output.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    switch (f) {
      case [
            'cpu',
            final policy,
            final governor,
            final cur,
            final min,
            final max,
          ]
          when _allInts([cur, min, max]):
        cpu[policy] = {
          'governor': governor,
          'curKHz': int.parse(cur),
          'minKHz': int.parse(min),
          'maxKHz': int.parse(max),
        };
      case ['gpu', final cur, final min, final max]
          when _allInts([cur, min, max]):
        gpu = {
          'curMHz': int.parse(cur),
          'minMHz': int.parse(min),
          'maxMHz': int.parse(max),
        };
    }
  }
  return {if (cpu.isNotEmpty) 'cpu': cpu, 'gpu': ?gpu};
}

bool _allInts(List<String> values) =>
    values.every((v) => int.tryParse(v) != null);
