import 'dart:math';

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _android = AttachPolicy.android();
const _ios = AttachPolicy.ios();
const _desktop = AttachPolicy.desktop();
const _web = AttachPolicy.web();
const _all = [_android, _ios, _desktop, _web];

const _caption = RichText.plain('hello');

/// The plan in a short form: `G(a*,b)` a send group, `S(a)` a single, `T*`
/// the caption as text, `F` a file form, `A` an audio form; `*` marks where
/// the caption went.
List<String> _shape(SendPlan plan) => switch (plan) {
  SendPlan$Rejected(:final rejection) => ['rejected: ${rejection.name}'],
  SendPlan$Ready(:final sends) => [
    for (final send in sends)
      switch (send) {
        PlannedSend$Single(:final item, :final caption, :final form) =>
          '${_form(form)}S(${item.id}${caption == null ? '' : '*'})',
        PlannedSend$Group(:final items, :final captionIndex, :final form) =>
          '${_form(form)}G(${[for (var i = 0; i < items.length; i++) '${items[i].id}${i == captionIndex ? '*' : ''}'].join(',')})',
        PlannedSend$Text() => 'T*',
      },
  ],
};

String _form(SendForm form) => switch (form) {
  SendForm.media => '',
  SendForm.file => 'F',
  SendForm.audio => 'A',
};

List<String> _plan(
  AttachPolicy policy,
  List<AttachItem> items, {
  RichText caption = RichText.empty,
  SendOptions options = const SendOptions(),
  AttachLimits limits = const AttachLimits(),
}) => _shape(
  planSend(
    SendRequest(items: items, caption: caption, options: options),
    policy,
    limits,
  ),
);

List<AttachItem> _photos(int n, [String prefix = 'p']) => [
  for (var i = 0; i < n; i++) AttachItems.photo('$prefix$i'),
];

void main() {
  group('groups of at most ten', () {
    test('25 mixed photos and videos make 3 groups on every policy', () {
      final items = [
        for (var i = 0; i < 25; i++)
          i.isEven ? AttachItems.photo('m$i') : AttachItems.video('m$i'),
      ];
      for (final policy in _all) {
        final plan = _plan(policy, items);
        expect(plan, hasLength(3), reason: '$policy');
        expect(plan[0], startsWith('G(m0,m1,'));
        expect(plan[2], 'G(m20,m21,m22,m23,m24)');
      }
    });

    test('150 photos on desktop make 15 groups', () {
      final plan = _plan(_desktop, _photos(150));
      expect(plan, hasLength(15));
      expect(plan.last, 'G(p140,p141,p142,p143,p144,p145,p146,p147,p148,p149)');
    });

    test('a group of one is a single', () {
      expect(_plan(_android, _photos(11)), [
        'G(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9)',
        'S(p10)',
      ]);
    });
  });

  group('what shares a group', () {
    test('a lone file inside photos breaks the run', () {
      final items = [..._photos(2), AttachItems.file('f'), ..._photos(2, 'q')];
      for (final policy in _all) {
        expect(_plan(policy, items), [
          'G(p0,p1)',
          'FS(f)',
          'G(q0,q1)',
        ], reason: '$policy');
      }
    });

    test('files group with files, audio with audio', () {
      final items = [
        AttachItems.file('f0'),
        AttachItems.file('f1'),
        AttachItems.audio('a0'),
        AttachItems.audio('a1'),
      ];
      expect(_plan(_android, items), ['FG(f0,f1)', 'AG(a0,a1)']);
    });

    test('as files, photos and videos group as files', () {
      final items = [
        AttachItems.photo('p'),
        AttachItems.video('v'),
        AttachItems.file('f'),
      ];
      expect(_plan(_ios, items, options: const SendOptions(asFiles: true)), [
        'FG(p,v,f)',
      ]);
    });

    test('grouping off gives one single per item', () {
      for (final policy in _all) {
        expect(
          _plan(policy, _photos(3), options: const SendOptions(grouped: false)),
          ['S(p0)', 'S(p1)', 'S(p2)'],
          reason: '$policy',
        );
      }
    });

    test('limits without grouping (slow mode) give singles', () {
      expect(
        _plan(
          _android,
          _photos(2),
          limits: const AttachLimits(groupingAllowed: false),
        ),
        ['S(p0)', 'S(p1)'],
      );
    });

    test('a spoiler never breaks a group, on every policy', () {
      final items = [
        AttachItems.photo('p0'),
        AttachItems.photo('p1', spoiler: true),
        AttachItems.video('v', spoiler: true),
        AttachItems.photo('p2'),
      ];
      for (final policy in _all) {
        final plan = planSend(
          SendRequest(items: items, caption: RichText.empty),
          policy,
          const AttachLimits(),
        );
        expect(_shape(plan), ['G(p0,p1,v,p2)'], reason: '$policy');
        final group =
            (plan as SendPlan$Ready).sends.single as PlannedSend$Group;
        expect(group.items.map((i) => i.spoiler), [false, true, true, false]);
      }
    });
  });

  group('what breaks a group', () {
    final timed = AttachItems.photo('t', timer: const AttachTimer.once());
    final middle = [..._photos(2), timed, ..._photos(2, 'q')];

    test('Android: only the item with a timer leaves its group', () {
      expect(_plan(_android, middle), ['G(p0,p1)', 'S(t)', 'G(q0,q1)']);
    });

    test('desktop and iOS: any timer ungroups the batch', () {
      for (final policy in [_desktop, _ios]) {
        expect(_plan(policy, middle), [
          'S(p0)',
          'S(p1)',
          'S(t)',
          'S(q0)',
          'S(q1)',
        ], reason: '$policy');
      }
    });

    test('web: a timer leaves its group only', () {
      expect(_plan(_web, middle), ['G(p0,p1)', 'S(t)', 'G(q0,q1)']);
    });

    final withGif = [
      ..._photos(2),
      AttachItems.animation('g'),
      ..._photos(2, 'q'),
    ];

    test('a GIF is never grouped; Android and desktop keep the rest', () {
      for (final policy in [_android, _desktop]) {
        expect(_plan(policy, withGif), [
          'G(p0,p1)',
          'S(g)',
          'G(q0,q1)',
        ], reason: '$policy');
      }
    });

    test('a GIF ungroups the batch on iOS and the web', () {
      for (final policy in [_ios, _web]) {
        expect(_plan(policy, withGif), [
          'S(p0)',
          'S(p1)',
          'S(g)',
          'S(q0)',
          'S(q1)',
        ], reason: '$policy');
      }
    });

    test('an edited video whose output is muted ungroups the batch on iOS', () {
      final muted = AttachItems.video(
        'v',
        derived: const DerivedOutput(localKey: 'local:v', muted: true),
      );
      final items = [..._photos(2), muted];
      expect(_plan(_ios, items), ['S(p0)', 'S(p1)', 'S(v)']);
      expect(_plan(_android, items), ['G(p0,p1,v)']);
    });

    test('as files, timers are cleared and the batch groups', () {
      final plan = planSend(
        SendRequest(
          items: middle,
          caption: RichText.empty,
          options: const SendOptions(asFiles: true),
        ),
        _desktop,
        const AttachLimits(),
      );
      expect(_shape(plan), ['FG(p0,p1,t,q0,q1)']);
      final group = (plan as SendPlan$Ready).sends.single as PlannedSend$Group;
      expect(group.items.every((i) => i.timer == null), isTrue);
    });
  });

  group('caption placement', () {
    final mixed = [..._photos(12), AttachItems.file('f')];

    test('Android: the first item of the first group', () {
      expect(_plan(_android, mixed, caption: _caption), [
        'G(p0*,p1,p2,p3,p4,p5,p6,p7,p8,p9)',
        'G(p10,p11)',
        'FS(f)',
      ]);
    });

    test('iOS: the first item when grouped, the last when not', () {
      expect(_plan(_ios, _photos(3), caption: _caption), ['G(p0*,p1,p2)']);
      expect(
        _plan(
          _ios,
          _photos(3),
          caption: _caption,
          options: const SendOptions(grouped: false),
        ),
        ['S(p0)', 'S(p1)', 'S(p2*)'],
      );
    });

    test('desktop: the first item of the last group when it is media', () {
      expect(_plan(_desktop, _photos(12), caption: _caption), [
        'G(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9)',
        'G(p10*,p11)',
      ]);
    });

    test('desktop: else the last item', () {
      expect(_plan(_desktop, mixed, caption: _caption), [
        'G(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9)',
        'G(p10,p11)',
        'FS(f*)',
      ]);
      expect(
        _plan(_desktop, [
          AttachItems.file('f0'),
          AttachItems.file('f1'),
        ], caption: _caption),
        ['FG(f0,f1*)'],
      );
    });

    test('web: the first send when there is one', () {
      expect(_plan(_web, _photos(3), caption: _caption), ['G(p0*,p1,p2)']);
    });

    test('web: a text send ahead of two or more groups', () {
      expect(_plan(_web, _photos(12), caption: _caption), [
        'T*',
        'G(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9)',
        'G(p10,p11)',
      ]);
    });

    test('a caption alone is a text send', () {
      for (final policy in _all) {
        expect(_plan(policy, const [], caption: _caption), ['T*']);
      }
    });

    test('the group carries the caption it marks', () {
      final plan = planSend(
        SendRequest(items: _photos(2), caption: _caption),
        _android,
        const AttachLimits(),
      );
      final group = (plan as SendPlan$Ready).sends.single as PlannedSend$Group;
      expect(group.caption, _caption);
      expect(plan.caption, _caption);
    });
  });

  group('rejections', () {
    test('nothing to send', () {
      expect(_plan(_android, const []), ['rejected: empty']);
    });

    test('a caption over the limit', () {
      expect(
        _plan(
          _ios,
          _photos(1),
          caption: const RichText.plain('12345'),
          limits: const AttachLimits(captionLength: 4),
        ),
        ['rejected: captionTooLong'],
      );
      expect(
        _plan(
          _ios,
          _photos(1),
          caption: const RichText.plain('1234'),
          limits: const AttachLimits(captionLength: 4),
        ),
        ['S(p0*)'],
      );
    });

    test('a timer with a schedule', () {
      expect(
        _plan(_android, [
          AttachItems.photo('t', timer: const AttachTimer.once()),
        ], options: SendOptions(schedule: SendSchedule.at(DateTime(2030)))),
        ['rejected: timerWithSchedule'],
      );
      expect(
        _plan(_android, [
          AttachItems.photo('t', timer: const AttachTimer.once()),
        ], options: const SendOptions(schedule: SendSchedule.whenOnline())),
        ['rejected: timerWithSchedule'],
      );
    });

    test('a schedule the limits do not allow', () {
      expect(
        _plan(
          _desktop,
          _photos(1),
          options: const SendOptions(schedule: SendSchedule.whenOnline()),
          limits: const AttachLimits(scheduleAllowed: false),
        ),
        ['rejected: scheduleNotAllowed'],
      );
    });
  });

  test('the ready plan carries the options preparation reads', () {
    const options = SendOptions(highQuality: true, videoPreset: 848);
    final plan = planSend(
      SendRequest(items: _photos(1), caption: RichText.empty, options: options),
      _ios,
      const AttachLimits(),
    );
    expect((plan as SendPlan$Ready).options, options);
  });

  test('every item appears once, in order, in every plan', () {
    final random = Random(46);
    AttachItem pick(int i) => switch (random.nextInt(7)) {
      0 => AttachItems.photo('i$i'),
      1 => AttachItems.video('i$i'),
      2 => AttachItems.animation('i$i'),
      3 => AttachItems.audio('i$i'),
      4 => AttachItems.file('i$i'),
      5 => AttachItems.photo('i$i', timer: const AttachTimer.once()),
      _ => AttachItems.photo('i$i', spoiler: true),
    };
    for (var run = 0; run < 300; run++) {
      final items = [for (var i = 0; i < random.nextInt(60); i++) pick(i)];
      final options = SendOptions(
        grouped: random.nextBool(),
        asFiles: random.nextBool(),
      );
      final caption = random.nextBool() ? _caption : RichText.empty;
      for (final policy in _all) {
        final plan = planSend(
          SendRequest(items: items, caption: caption, options: options),
          policy,
          const AttachLimits(),
        );
        if (plan case SendPlan$Rejected()) {
          expect(items.isEmpty && caption.isEmpty, isTrue);
          continue;
        }
        final sends = (plan as SendPlan$Ready).sends;
        final sent = [
          for (final send in sends)
            ...switch (send) {
              PlannedSend$Single(:final item) => [item.id],
              PlannedSend$Group(:final items) => [
                for (final item in items) item.id,
              ],
              PlannedSend$Text() => const <AttachItemId>[],
            },
        ];
        expect(sent, [for (final item in items) item.id]);
        for (final send in sends) {
          if (send case PlannedSend$Group(:final items)) {
            expect(items.length, inInclusiveRange(2, 10));
          }
        }
        final captions = sends.where(
          (s) => switch (s) {
            PlannedSend$Single(:final caption) => caption != null,
            PlannedSend$Group(:final captionIndex) => captionIndex != null,
            PlannedSend$Text() => true,
          },
        );
        expect(captions.length, caption.isEmpty ? 0 : 1);
      }
    }
  });
}
