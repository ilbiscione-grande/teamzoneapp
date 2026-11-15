// The browser's recording rewritten as an ordinary video file, without
// encoding it again. MediaRecorder writes MP4 in fragments and WebM without a
// length, so some players showed a video of two hours that failed where the
// recording ended. Rewritten, the file has its true length up front.
import { ALL_FORMATS, BlobSource, BufferTarget, Conversion, Input, Mp4OutputFormat, Output, WebMOutputFormat } from "mediabunny";

/** The same video with its true length; the recording as it is when it cannot be rewritten. */
export async function finishVideo(recording: Blob, mp4: boolean): Promise<Blob> {
  try {
    const input = new Input({ source: new BlobSource(recording), formats: ALL_FORMATS });
    const output = new Output({
      format: mp4 ? new Mp4OutputFormat({ fastStart: "in-memory" }) : new WebMOutputFormat(),
      target: new BufferTarget(),
    });
    const conversion = await Conversion.init({ input, output, showWarnings: false });
    if (!conversion.isValid) return recording;
    await conversion.execute();
    const buffer = (output.target as BufferTarget).buffer;
    return buffer ? new Blob([buffer], { type: mp4 ? "video/mp4" : "video/webm" }) : recording;
  } catch {
    return recording;
  }
}
