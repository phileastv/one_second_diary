import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:saf/saf.dart';
// import 'package:tapioca/tapioca.dart';
import 'package:video_player/video_player.dart';

import '../../../controllers/daily_entry_controller.dart';
import '../../../controllers/video_count_controller.dart';
import '../../../routes/app_pages.dart';
import '../../../utils/custom_dialog.dart';
import '../../../utils/date_format_utils.dart';
import '../../../utils/ffmpeg_api_wrapper.dart';
import '../../../utils/shared_preferences_util.dart';
import '../../../utils/storage_utils.dart';
import '../../../utils/utils.dart';
// import '../../../utils/utils.dart';

class SaveButton extends StatefulWidget {
  SaveButton({
    required this.videoPath,
    required this.videoController,
    required this.dateColor,
    required this.dateFormat,
    required this.isTextDate,
    required this.userLocation,
    required this.isGeotaggingEnabled,
  });

  // Finding controllers
  final String videoPath;
  final VideoPlayerController videoController;
  final Color dateColor;
  final String dateFormat;
  final bool isTextDate;
  final String? userLocation;
  final bool isGeotaggingEnabled;

  @override
  _SaveButtonState createState() => _SaveButtonState();
}

class _SaveButtonState extends State<SaveButton> {
  bool isProcessing = false;

  final DailyEntryController _dayController = Get.find();

  final VideoCountController _videoCountController = Get.find();

  void _saveVideo() async {
    print('Starting to save video');
    setState(() {
      isProcessing = true;
    });

    try {
      // await _editWithTapicoa(datePosX, datePosY, size, isEdit);

      // Alternative way of editing video, using ffmpeg, but it is very slow
      await _editWithFFmpeg(widget.isGeotaggingEnabled, context);

      setState(() {
        isProcessing = false;
      });
    } catch (e) {
      print(e);

      // Deleting video from cache
      StorageUtils.deleteFile(widget.videoPath);

      setState(() {
        isProcessing = false;
      });
      // Utils().logError('$e');
      // Showing error popup
      await showDialog(
        barrierDismissible: false,
        context: Get.context!,
        builder: (context) => CustomDialog(
          isDoubleAction: false,
          title: 'saveVideoErrorTitle'.tr,
          content: '${'tryAgainMsg'.tr}\n\nError: ${e.toString()}',
          actionText: 'Ok',
          actionColor: Colors.red,
          action: () => Get.offAllNamed(Routes.HOME),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool _pressedSave = false;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.45,
      height: MediaQuery.of(context).size.height * 0.08,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 5.0,
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(80.0),
          ),
        ),
        child: !isProcessing
            ? Text(
                'save'.tr,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width * 0.07,
                ),
              )
            : const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white,
                ),
              ),
        onPressed: () {
          // Prevents user from clicking it twice
          if (!_pressedSave) {
            _pressedSave = true;
            _saveVideo();
          }
        },
      ),
    );
  }

  Future<void> _editWithFFmpeg(bool isGeotaggingEnabled, BuildContext context) async {
    // Positions to render texts for the (x, y co-ordinates)
    // According to the ffmpeg docs, the x, y positions are relative to the top-left side of the output frame.
    final String datePosY = widget.isTextDate ? 'h-th-40' : '40';
    final String datePosX = widget.isTextDate ? '40' : 'w-tw-40';
    const String locPosY = 'h-th-40';
    const String locPosX = 'w-tw-40';

    final double dateTextSize = MediaQuery.of(context).size.width * 0.032 * 2.5;
    final double locTextSize = MediaQuery.of(context).size.width * 0.032 * 2.67;

    String locOutput = '';

    // Used to not increment videoCount controller
    bool isEdit = false;

    // Copies text font for ffmpeg to storage if it was not copied yet
    final String fontPath = await Utils.copyFontToStorage();
    final String videoPath = widget.videoPath;

    // Parses the color code to a hex code format which can be read by ffmpeg
    final String parsedDateColor =
        '0x${widget.dateColor.value.toRadixString(16).substring(2)}';

    // Path to save the final video
    final String finalPath =
        '${SharedPrefsUtil.getString('appPath')}${DateFormatUtils.getToday()}.mp4';

    // Check if video already exists and delete it if so (Edit daily feature)
    if (StorageUtils.checkFileExists(finalPath)) {
      isEdit = true;
      StorageUtils.deleteFile(finalPath);
    }

    // Checks to ensure special read/write permissions with storage access framework
    final hasSafDirPerms = await Saf.isPersistedPermissionDirectoryFor(finalPath) ?? false;
    if (hasSafDirPerms) {
      await Saf(finalPath).getDirectoryPermission(isDynamic: true);
    }

    // If geotagging is enabled, we can allow the command to render the location text into the video
    if (isGeotaggingEnabled) {
      locOutput =
          ', drawtext=$fontPath:text=\'${widget.userLocation}\':fontsize=$locTextSize:fontcolor=\'$parsedDateColor\':x=$locPosX:y=$locPosY';
    }

    // Caches the default font to save texts in ffmpeg.
    // The edit may fail unexpectedly in some devices if this is not done.
    await FFmpegKitConfig.setFontDirectory(fontPath);

    await executeFFmpeg(
      '-i $videoPath -vf [in]drawtext="$fontPath:text=\'${widget.dateFormat}\':fontsize=$dateTextSize:fontcolor=\'$parsedDateColor\':x=$datePosX:y=$datePosY$locOutput[out]" -codec:v libx264 -pix_fmt yuv420p $finalPath -y',
    ).then((session) async {
      print(session.getCommand().toString());
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        print('Video edited successfully');

        _dayController.updateDaily();

        // Updates the controller: videoCount += 1
        if (!isEdit) {
          _videoCountController.updateVideoCount();
        }

        // Showing confirmation popup
        showDialog(
          barrierDismissible: false,
          context: Get.context!,
          builder: (context) => CustomDialog(
            isDoubleAction: false,
            title: 'videoSavedTitle'.tr,
            content: 'videoSavedDesc'.tr,
            actionText: 'Ok',
            actionColor: Colors.green,
            action: () => Get.offAllNamed(Routes.HOME),
          ),
        );
      } else if (ReturnCode.isCancel(returnCode)) {
        print('Execution was cancelled');
      } else {
        print('Error editing video: Return code is ${await session.getReturnCode()}');
        final sessionLog = await session.getAllLogsAsString();
        final failureStackTrace = await session.getFailStackTrace();
        debugPrint('Session lasted for ${await session.getDuration()} ms');
        debugPrint(session.getArguments().toString());
        debugPrint('Session log is $sessionLog');
        debugPrint('Failure stacktrace - $failureStackTrace');
      }
    });
  }

  // Future<void> _editWithTapicoa(int x, int y, int size, bool isEdit) async {
  //   // Utils().logInfo('Saving video...');

  //   // Creates the folder if it is not created yet
  //   await StorageUtils.createFolder();

  //   // Setting editing properties
  //   final Cup cup = Cup(
  //     Content(widget.videoPath),
  //     [
  //       TapiocaBall.textOverlay(
  //         // Date in the proper format
  //         widget.dateFormat,
  //         x,
  //         y,
  //         size,
  //         widget.dateColor,
  //       ),
  //     ],
  //   );

  //   // Path to save the final video
  //   final String finalPath =
  //       '${SharedPrefsUtil.getString('appPath')}${DateFormatUtils.getToday()}.mp4';

  //   // Check if video already exists and delete it if so (Edit daily feature)
  //   if (StorageUtils.checkFileExists(finalPath)) {
  //     isEdit = true;
  //     // Utils().logWarning('File already exists!');
  //     StorageUtils.deleteFile(finalPath);
  //     // Utils().logWarning('Old file deleted!');
  //   }

  //   // Editing video
  //   await cup.suckUp(finalPath).then(
  //     (_) {
  //       _dayController.updateDaily();

  //       // Updates the controller: videoCount += 1
  //       if (!isEdit) {
  //         _videoCountController.updateVideoCount();
  //       }

  //       // Deleting video from cache
  //       StorageUtils.deleteFile(widget.videoPath);

  //       // Stop loading animation
  //       setState(() {
  //         isProcessing = false;
  //       });

  //       // Showing confirmation popup
  //       showDialog(
  //         barrierDismissible: false,
  //         context: Get.context!,
  //         builder: (context) => CustomDialog(
  //           isDoubleAction: false,
  //           title: 'videoSavedTitle'.tr,
  //           content: 'videoSavedDesc'.tr,
  //           actionText: 'Ok',
  //           actionColor: Colors.green,
  //           action: () => Get.offAllNamed(Routes.HOME),
  //         ),
  //       );
  //     },
  //   );
  // }
}
