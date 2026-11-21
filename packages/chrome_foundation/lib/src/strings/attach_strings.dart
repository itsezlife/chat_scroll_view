/// Strings of the attach sheet's own chrome: the questions asked before a
/// selection is thrown away, and its stock page labels.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Which question a platform asks is the sheet policy's; both
/// wordings live here.
final class AttachStrings {
  /// Attach strings with every member given.
  const AttachStrings({
    required this.discardSelectionTitle,
    required this.libraryHighQuality,
    required this.discardSelectionMessage,
    required this.discardSelectionConfirm,
    required this.discardSelectionKeep,
    required this.cancelSelectionTitle,
    required this.cancelSelectionConfirm,
    required this.cancelSelectionKeep,
    required this.galleryTab,
    required this.filesTab,
    required this.permissionNeeded,
    required this.captionPlaceholder,
    required this.sendAction,
    required this.moreOptions,
    required this.sendSilently,
    required this.schedule,
    required this.sendWhenOnline,
    required this.captionAbove,
    required this.captionBelow,
    required this.openExternal,
    required this.sendAsFile,
    required this.sendAsFiles,
    required this.sendWithoutGrouping,
    required this.enableSpoiler,
    required this.disableSpoiler,
    required this.highQuality,
    required this.standardQuality,
    required this.sendInHd,
    required this.libraryPhoto,
    required this.libraryVideo,
    required this.libraryOpen,
    required this.librarySelect,
    required this.libraryGif,
    required this.libraryNoAccess,
    required this.libraryAllowAccess,
    required this.libraryEmpty,
    required this.chooseFromGallery,
    required this.chooseFromFiles,
    required this.recentFiles,
    required this.sendPhoto,
    required this.sendVideo,
    required this.sendFile,
    required this.sendGif,
    required this.groupItems,
    required this.sendAsDocuments,
    required this.remember,
    required this.addItems,
    required this.cancelAction,
    required this.deleteItem,
    required this.replaceItem,
    required this.editItem,
    required this.setTimer,
    required this.sendAsMedia,
    required this.groupAll,
    required this.ungroupAll,
    required this.dropAsFiles,
    required this.dropAsMedia,
    required this.dropAdd,
    required this.photosSelected,
    required this.filesSelected,
    required this.sendPhotos,
    required this.sendVideos,
    required this.sendFiles,
    required this.albumAllMedia,
    required this.albumAllPhotos,
    required this.albumAllVideos,
    required this.albumCamera,
    required this.albumFavourites,
    required this.libraryDeniedTitle,
    required this.libraryOpenSettings,
    required this.libraryCamera,
    required this.libraryRestricted,
    required this.libraryLimited,
    required this.libraryManage,
    required this.librarySelectMore,
    required this.libraryChangeSettings,
    required this.libraryPartial,
    required this.libraryCameraDenied,
    required this.libraryMonth,
    required this.mediaNotAllowed,
    required this.captureClose,
    required this.captureShutter,
    required this.captureSwitchCamera,
    required this.captureFlash,
    required this.captureVideoNotAllowed,
    required this.captureVideoMode,
    required this.capturePhotoMode,
    required this.captureMicrophoneDenied,
  });

  /// The question before a selection is dropped, in the "discard" wording
  /// ("Discard selection?").
  final String discardSelectionTitle;

  /// The mark on a checked photo sent in high quality ("HD").
  final String libraryHighQuality;

  /// The line under it ("Do you want to close the attach menu?").
  final String discardSelectionMessage;

  /// Its action that drops the selection ("Discard").
  final String discardSelectionConfirm;

  /// Its action that keeps the sheet open ("Cancel").
  final String discardSelectionKeep;

  /// The question in the "cancel" wording ("Cancel selection?").
  final String cancelSelectionTitle;

  /// Its action that drops the selection ("Yes").
  final String cancelSelectionConfirm;

  /// Its action that keeps the sheet open ("No").
  final String cancelSelectionKeep;

  /// The label of the stock Gallery page's tab.
  final String galleryTab;

  /// The label of the stock Files page's tab.
  final String filesTab;

  /// The spoken name of a tab's badge when its page lacks a permission.
  final String permissionNeeded;

  /// The caption field's placeholder ("Add a caption…").
  final String captionPlaceholder;

  /// The send button's spoken label ("Send").
  final String sendAction;

  /// The spoken label of the header's overflow button ("More").
  final String moreOptions;

  /// The send menu's "Send without sound".
  final String sendSilently;

  /// The send menu's "Schedule message".
  final String schedule;

  /// The send menu's "Send when online".
  final String sendWhenOnline;

  /// The menu entry that moves the caption above the media.
  final String captionAbove;

  /// The menu entry that moves the caption below the media.
  final String captionBelow;

  /// The overflow entry that opens the system picker.
  final String openExternal;

  /// The overflow entry that sends one item as a file.
  final String sendAsFile;

  /// The overflow entry that sends the items as files.
  final String sendAsFiles;

  /// The overflow entry that sends each item on its own.
  final String sendWithoutGrouping;

  /// The overflow entry that hides the media under a spoiler.
  final String enableSpoiler;

  /// The overflow entry that removes the spoiler.
  final String disableSpoiler;

  /// The overflow entry that switches to high quality.
  final String highQuality;

  /// The overflow entry that switches back to standard quality.
  final String standardQuality;

  /// The overflow entry that sends in high quality now.
  final String sendInHd;

  /// The spoken kind of a photo cell.
  final String libraryPhoto;

  /// The spoken kind of a video cell.
  final String libraryVideo;

  /// The spoken action that opens a cell.
  final String libraryOpen;

  /// The spoken action that selects a cell.
  final String librarySelect;

  /// The badge of a GIF cell.
  final String libraryGif;

  /// The Gallery page without access to the library.
  final String libraryNoAccess;

  /// Its button.
  final String libraryAllowAccess;

  /// The Gallery page with an empty library.
  final String libraryEmpty;

  /// The Files page row that picks from the gallery as files.
  final String chooseFromGallery;

  /// The Files page row that opens the file dialog.
  final String chooseFromFiles;

  /// The header of the Files page's recent files.
  final String recentFiles;

  /// The confirm box title for one photo.
  final String sendPhoto;

  /// The confirm box title for one video.
  final String sendVideo;

  /// The confirm box title for one file.
  final String sendFile;

  /// The confirm box title for one GIF.
  final String sendGif;

  /// The confirm box checkbox that groups items.
  final String groupItems;

  /// The confirm box checkbox that sends media as files.
  final String sendAsDocuments;

  /// The confirm box checkbox that remembers the choice.
  final String remember;

  /// The confirm box action that adds files.
  final String addItems;

  /// The confirm box action that closes it.
  final String cancelAction;

  /// An item action that removes it.
  final String deleteItem;

  /// An item action that replaces it.
  final String replaceItem;

  /// An item action that edits it.
  final String editItem;

  /// An item action that sets a self-destruct timer.
  final String setTimer;

  /// The More menu entry that sends files as media.
  final String sendAsMedia;

  /// The More menu entry that groups every item.
  final String groupAll;

  /// The More menu entry that sends each item on its own.
  final String ungroupAll;

  /// The drop zone that sends files without compression.
  final String dropAsFiles;

  /// The drop zone that sends media.
  final String dropAsMedia;

  /// The drop zone over an open confirm box.
  final String dropAdd;

  /// The confirm box title for several photos and videos.
  final String Function(int n) photosSelected;

  /// The confirm box title for several files.
  final String Function(int n) filesSelected;

  /// The web box title for several photos.
  final String Function(int n) sendPhotos;

  /// The web box title for several videos.
  final String Function(int n) sendVideos;

  /// The web box title for several files or a mix.
  final String Function(int n) sendFiles;

  /// The library album of every photo and video.
  final String albumAllMedia;

  /// The library album of every photo.
  final String albumAllPhotos;

  /// The library album of every video.
  final String albumAllVideos;

  /// The camera's library album.
  final String albumCamera;

  /// The favourites album.
  final String albumFavourites;

  /// The Gallery page's title when access is denied.
  final String libraryDeniedTitle;

  /// The button that opens the system settings.
  final String libraryOpenSettings;

  /// The camera cell's spoken label and the denied state's camera button.
  final String libraryCamera;

  /// The Gallery page when the system restricts the library.
  final String libraryRestricted;

  /// The banner when only some items were shared.
  final String libraryLimited;

  /// The banner's button.
  final String libraryManage;

  /// The manage menu entry that picks more items.
  final String librarySelectMore;

  /// The manage menu entry that opens the settings.
  final String libraryChangeSettings;

  /// The banner when the system shares selected items only.
  final String libraryPartial;

  /// The banner when the camera is denied.
  final String libraryCameraDenied;

  /// The month a library item was taken in, with its year, as the Gallery
  /// page's fast scroll label names it ("March 2024").
  final String Function(DateTime date) libraryMonth;

  /// The Gallery page where media cannot be sent.
  final String mediaNotAllowed;

  /// The capture surface's close button.
  final String captureClose;

  /// The capture surface's shutter.
  final String captureShutter;

  /// The capture surface's switch button.
  final String captureSwitchCamera;

  /// The capture surface's flash button.
  final String captureFlash;

  /// The notice when a hold on the capture surface asks for a video where
  /// only photos may be sent ("Videos can't be sent here").
  final String captureVideoNotAllowed;

  /// The capture surface's video mode, in its mode control ("VIDEO").
  final String captureVideoMode;

  /// The capture surface's photo mode, in its mode control ("PHOTO").
  final String capturePhotoMode;

  /// The notice when the microphone a video needs was refused, with where
  /// to allow it ("Allow the microphone in Settings to record video").
  final String captureMicrophoneDenied;
}
