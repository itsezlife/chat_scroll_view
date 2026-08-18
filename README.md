# chat_scroll_view

Endless, anchor-based chat viewport for Flutter. Layout fans out from
`(anchorMessageId, anchorPixelOffset)` instead of a global content height.

## Usage

```dart
import 'package:chat_scroll_view/chat_scroll_view.dart';

ChatScrollView(
  dataSource: dataSource,
  controller: controller,
  messageBuilder: (context, id, message, status, runLayout) {
    if (message == null) return const ShimmerMessage();
    return Text(message.sender);
  },
)
```

Implement [ChatDataSource.fetchRange] for your backend. The example app
under `example/` wires a Supabase demo and an offline comments dataset.

## Example

```sh
cd example
flutter run --dart-define-from-file=../config/development.supabase.json
```

Start the local demo backend first: `./scripts/dev.sh`.
