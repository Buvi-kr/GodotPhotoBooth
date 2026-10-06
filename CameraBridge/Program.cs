// Windows camera bridge using the inbox Video for Windows API and .NET Framework.
// Top-down RGB frames are sent over loopback for Godot display, sampling and chroma processing.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new BridgeForm(ArgInt(args, "--width", 1920), ArgInt(args, "--height", 1080), ArgInt(args, "--fps", 30), ArgInt(args, "--port", 49152), ArgString(args, "--device", "")));
    }
    private static int ArgInt(string[] args, string key, int fallback)
    {
        int at = Array.IndexOf(args, key), value;
        return at >= 0 && at + 1 < args.Length && int.TryParse(args[at + 1], out value) ? value : fallback;
    }
    private static string ArgString(string[] args, string key, string fallback)
    {
        int at = Array.IndexOf(args, key);
        return at >= 0 && at + 1 < args.Length ? args[at + 1] : fallback;
    }
}

internal sealed class BridgeForm : Form
{
    private const int WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000;
    private const uint START = 0x0400, DRIVER_CONNECT = START + 10, DRIVER_DISCONNECT = START + 11,
        GET_FORMAT = START + 44, SET_FORMAT = START + 45, PREVIEW = START + 50, PREVIEW_RATE = START + 52, SET_FRAME_CALLBACK = START + 5,
        SET_STREAM_CALLBACK = START + 6, SEQUENCE_NOFILE = START + 63, SET_SEQUENCE_SETUP = START + 64,
        GET_SEQUENCE_SETUP = START + 65, STOP_CAPTURE = START + 68, BI_RGB = 0, MJPG = 1196444237;
    private readonly int width, height, fps, port;
    private readonly string preferredDevice;
    private readonly object frameLock = new object();
    private readonly object captureLock = new object();
    private IntPtr captureWindow = IntPtr.Zero;
    private CaptureCallback callback;
    private byte[] captureBuffer;
    private byte[] latestFrame;
    private int latestFrameFormat;
    private long latestFrameVersion;
    private long lastSentFrameVersion;
    private int cameraWidth, cameraHeight, cameraStride;
    private uint cameraCompression;
    private ushort cameraBitCount;
    private bool cameraFormatSupported;
    private bool cameraBottomUp;
    private TcpListener listener;
    private TcpClient client;
    private NetworkStream stream;
    private Thread acceptThread;
    private volatile bool stopping, writing;
    private long lastFrame;
    private long sourceRateWindowStart;
    private int sourceRateFrameCount;
    private bool firstCallbackLogged, invalidFrameLogged, firstFrameLogged, firstFrameSentLogged, firstSendStateLogged;
    private string logPath;

    internal BridgeForm(int w, int h, int rate, int socketPort, string deviceName)
    {
        width = w; height = h; fps = Math.Max(1, Math.Min(60, rate)); port = socketPort; preferredDevice = deviceName ?? "";
        logPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "camera_bridge.log");
        ShowInTaskbar = false; FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual;
        // VFW preview callbacks are not reliably delivered by drivers when their
        // capture HWND is hidden or clipped to a 1x1 transparent parent.
        Location = new Point(-32000, -32000); Size = new Size(Math.Max(320, Math.Min(w, 1920)), Math.Max(240, Math.Min(h, 1080))); Opacity = 1; Load += OnLoad; FormClosed += OnClosed;
    }

    private void OnLoad(object sender, EventArgs e)
    {
        try
        {
            listener = new TcpListener(IPAddress.Loopback, port); listener.Start();
            acceptThread = new Thread(AcceptClients); acceptThread.IsBackground = true; acceptThread.Start();
            Log("VFW camera initialization starting.");
            if (!ConnectCamera()) { Log("No VFW camera could be opened."); Close(); return; }
            Log("CAMERA_READY " + width + "x" + height + "@" + fps + " port=" + port);
            Thread senderThread = new Thread(SenderLoop); senderThread.IsBackground = true; senderThread.Name = "Camera frame sender"; senderThread.Start();
        }
        catch (Exception ex) { Log("BRIDGE_ERROR " + ex); Close(); }
    }

    private bool ConnectCamera()
    {
        Log("Creating VFW capture window.");
        captureWindow = capCreateCaptureWindowW("GodotCameraBridge", WS_CHILD | WS_VISIBLE, 0, 0, ClientSize.Width, ClientSize.Height, Handle, 0);
        Log("VFW capture window result: " + (captureWindow == IntPtr.Zero ? "failed" : "created"));
        if (captureWindow == IntPtr.Zero) return false;
        bool connected = false;
        if (!String.IsNullOrWhiteSpace(preferredDevice))
        {
            for (ushort i = 0; i < 10 && !connected; i++)
            {
                StringBuilder name = new StringBuilder(256), version = new StringBuilder(256);
                if (capGetDriverDescriptionW(i, name, name.Capacity, version, version.Capacity) && name.ToString().IndexOf(preferredDevice, StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    Log("Connecting configured VFW driver index=" + i + " name=" + name);
                    connected = SendMessage(captureWindow, DRIVER_CONNECT, (IntPtr)i, IntPtr.Zero) != IntPtr.Zero;
                    Log("Configured VFW driver index=" + i + " connected=" + connected);
                }
            }
            if (!connected) Log("Configured VFW camera not found: " + preferredDevice);
        }
        else
        {
            for (int i = 0; i < 10 && !connected; i++)
            {
                Log("Connecting default VFW driver index=" + i);
                connected = SendMessage(captureWindow, DRIVER_CONNECT, (IntPtr)i, IntPtr.Zero) != IntPtr.Zero;
                Log("Default VFW driver index=" + i + " connected=" + connected);
            }
        }
        if (!connected) return false;
        TrySetResolution(); callback = OnFrame;
        IntPtr callbackRegistered = SendMessage(captureWindow, SET_FRAME_CALLBACK, IntPtr.Zero, Marshal.GetFunctionPointerForDelegate(callback));
        Log("VFW frame callback registered=" + (callbackRegistered != IntPtr.Zero));
        SendMessage(captureWindow, PREVIEW_RATE, IntPtr.Zero, (IntPtr)(1000 / fps));
        IntPtr previewStarted = SendMessage(captureWindow, PREVIEW, (IntPtr)1, IntPtr.Zero);
        Log("VFW preview started=" + (previewStarted != IntPtr.Zero));
        ConfigureStreamCapture();
        IntPtr streamCallbackRegistered = SendMessage(captureWindow, SET_STREAM_CALLBACK, IntPtr.Zero, Marshal.GetFunctionPointerForDelegate(callback));
        Log("VFW stream callback registered=" + (streamCallbackRegistered != IntPtr.Zero));
        Thread captureThread = new Thread(delegate()
        {
            IntPtr captureStarted = SendMessage(captureWindow, SEQUENCE_NOFILE, IntPtr.Zero, IntPtr.Zero);
            Log("VFW no-file stream started=" + (captureStarted != IntPtr.Zero));
        });
        captureThread.IsBackground = true;
        captureThread.Name = "VFW capture stream";
        captureThread.Start();
        return true;
    }

    private void TrySetResolution()
    {
        int size = (int)SendMessage(captureWindow, GET_FORMAT, IntPtr.Zero, IntPtr.Zero);
        if (size >= Marshal.SizeOf(typeof(BitmapInfoHeader)) && size <= 1048576)
        {
            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                SendMessage(captureWindow, GET_FORMAT, (IntPtr)size, ptr);
                BitmapInfoHeader format = (BitmapInfoHeader)Marshal.PtrToStructure(ptr, typeof(BitmapInfoHeader));
                format.Width = width; format.Height = height; format.Planes = 1; format.BitCount = 24; format.Compression = BI_RGB;
                format.SizeImage = (uint)(((width * 3 + 3) & ~3) * height);
                Marshal.StructureToPtr(format, ptr, false); SendMessage(captureWindow, SET_FORMAT, (IntPtr)size, ptr);
            }
            finally { Marshal.FreeHGlobal(ptr); }
        }

        BitmapInfoHeader negotiatedFormat = ReadFormat();
        cameraWidth = Math.Abs(negotiatedFormat.Width);
        cameraHeight = Math.Abs(negotiatedFormat.Height);
        cameraCompression = negotiatedFormat.Compression;
        cameraBitCount = negotiatedFormat.BitCount;
        cameraFormatSupported = cameraCompression == MJPG || (cameraCompression == BI_RGB && cameraBitCount == 24);
        cameraStride = (cameraWidth * 3 + 3) & ~3;
        cameraBottomUp = negotiatedFormat.Height > 0;
        captureBuffer = cameraStride > 0 && cameraHeight > 0 ? new byte[cameraStride * cameraHeight] : null;
        Log("VFW_FORMAT requested=" + width + "x" + height + " RGB24 actual=" + cameraWidth + "x" + cameraHeight + " bitCount=" + negotiatedFormat.BitCount + " compression=" + CompressionName(cameraCompression) + " imageBytes=" + negotiatedFormat.SizeImage);
        if (!cameraFormatSupported) Log("UNSUPPORTED_CAMERA_FORMAT bitCount=" + cameraBitCount + " compression=" + CompressionName(cameraCompression));
    }

    private IntPtr OnFrame(IntPtr hwnd, ref VideoHeader header)
    {
        try
        {
            if (!firstCallbackLogged)
            {
                firstCallbackLogged = true;
                Log("FIRST_FRAME_CALLBACK_ENTRY data=" + (header.Data != IntPtr.Zero) + " buffer=" + header.BufferLength + " used=" + header.BytesUsed + " negotiated=" + cameraWidth + "x" + cameraHeight);
            }
            long now = Stopwatch.GetTimestamp();
            long minimumFrameTicks = Stopwatch.Frequency / fps;
            if (now - Interlocked.Read(ref lastFrame) < minimumFrameTicks) return IntPtr.Zero;
            Interlocked.Exchange(ref lastFrame, now);
            int w = cameraWidth, h = cameraHeight;
            int stride = cameraStride, required = stride * h;
            if (!cameraFormatSupported) return IntPtr.Zero;
            bool compressedMjpg = cameraCompression == MJPG;
            if (w < 16 || h < 16 || w > 8192 || h > 8192 || header.Data == IntPtr.Zero || header.BytesUsed == 0 || (compressedMjpg ? header.BytesUsed > header.BufferLength : (header.BufferLength < required || header.BytesUsed < required)))
            {
                if (!invalidFrameLogged)
                {
                    invalidFrameLogged = true;
                    Log("FIRST_FRAME_REJECTED required=" + required + " buffer=" + header.BufferLength + " used=" + header.BytesUsed + " width=" + w + " height=" + h + " format=" + CompressionName(cameraCompression));
                }
                return IntPtr.Zero;
            }
            lock (captureLock)
            {
                byte[] frame;
                int frameFormat;
                if (compressedMjpg)
                {
                    frame = new byte[(int)header.BytesUsed];
                    Marshal.Copy(header.Data, frame, 0, frame.Length);
                    frameFormat = 1;
                }
                else
                {
                    frame = new byte[w * h * 3];
                    frameFormat = 0;
                    byte[] pixels = captureBuffer;
                    if (pixels == null || pixels.Length < required) return IntPtr.Zero;
                    Marshal.Copy(header.Data, pixels, 0, required);
                    for (int y = 0; y < h; y++)
                    {
                        int sourceY = cameraBottomUp ? h - 1 - y : y;
                        int sourceOffset = sourceY * stride;
                        int destinationOffset = y * w * 3;
                        Buffer.BlockCopy(pixels, sourceOffset, frame, destinationOffset, w * 3);
                        for (int x = 0; x < w * 3; x += 3)
                        {
                            byte blue = frame[destinationOffset + x];
                            frame[destinationOffset + x] = frame[destinationOffset + x + 2];
                            frame[destinationOffset + x + 2] = blue;
                        }
                    }
                }
                lock (frameLock) { latestFrame = frame; latestFrameFormat = frameFormat; latestFrameVersion++; }
                RecordSourceFrameRate(now);
                if (!firstFrameLogged)
                {
                    firstFrameLogged = true;
                    Log("FIRST_FRAME_CALLBACK " + w + "x" + h + " format=" + (frameFormat == 1 ? "MJPEG" : "RGB24") + " bytes=" + frame.Length);
                }
            }
        }
        catch (Exception ex) { Log("FRAME_ERROR " + ex.Message); }
        return IntPtr.Zero;
    }

    private BitmapInfoHeader ReadFormat()
    {
        int size = (int)SendMessage(captureWindow, GET_FORMAT, IntPtr.Zero, IntPtr.Zero);
        if (size < Marshal.SizeOf(typeof(BitmapInfoHeader)) || size > 1048576) return new BitmapInfoHeader();
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try { SendMessage(captureWindow, GET_FORMAT, (IntPtr)size, ptr); return (BitmapInfoHeader)Marshal.PtrToStructure(ptr, typeof(BitmapInfoHeader)); }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    private void RecordSourceFrameRate(long now)
    {
        if (sourceRateWindowStart == 0) sourceRateWindowStart = now;
        sourceRateFrameCount++;
        long elapsedTicks = now - sourceRateWindowStart;
        long windowTicks = Stopwatch.Frequency * 5;
        if (elapsedTicks >= windowTicks)
        {
            double elapsedMs = elapsedTicks * 1000.0 / Stopwatch.Frequency;
            Log("CAMERA_SOURCE_RATE " + (sourceRateFrameCount * Stopwatch.Frequency / (double)elapsedTicks).ToString("F1") + "fps windowMs=" + elapsedMs.ToString("F0"));
            sourceRateWindowStart = now;
            sourceRateFrameCount = 0;
        }
    }

    private void ConfigureStreamCapture()
    {
        int size = Marshal.SizeOf(typeof(CaptureParameters));
        IntPtr memory = Marshal.AllocHGlobal(size);
        try
        {
            IntPtr got = SendMessage(captureWindow, GET_SEQUENCE_SETUP, (IntPtr)size, memory);
            if (got == IntPtr.Zero)
            {
                Log("VFW capture parameters unavailable; driver defaults will apply.");
                return;
            }
            CaptureParameters parameters = (CaptureParameters)Marshal.PtrToStructure(memory, typeof(CaptureParameters));
            parameters.RequestMicrosecondsPerFrame = (uint)Math.Max(1, 1000000 / fps);
            parameters.Yield = 1;
            parameters.CaptureAudio = 0;
            Marshal.StructureToPtr(parameters, memory, false);
            IntPtr updated = SendMessage(captureWindow, SET_SEQUENCE_SETUP, (IntPtr)size, memory);
            Log("VFW stream rate requested=" + fps + "fps captureSetup=" + (updated != IntPtr.Zero) + " yield=" + parameters.Yield);
        }
        finally { Marshal.FreeHGlobal(memory); }
    }

    private static string CompressionName(uint compression)
    {
        return compression == BI_RGB ? "RGB" : compression == MJPG ? "MJPG" : "0x" + compression.ToString("X8");
    }

    private void AcceptClients()
    {
        while (!stopping)
        {
            try
            {
                TcpClient next = listener.AcceptTcpClient(); next.NoDelay = true;
                lock (frameLock) { if (client != null) client.Close(); client = next; stream = next.GetStream(); lastSentFrameVersion = 0; }
                Log("TCP_CLIENT_ACCEPTED " + next.Client.RemoteEndPoint);
            }
            catch { if (!stopping) Thread.Sleep(200); }
        }
    }

    private void SendLatestFrame(object sender, EventArgs e)
    {
        if (writing) return;
        byte[] frame; NetworkStream target; int w, h, format; long version;
        lock (frameLock) { frame = latestFrame; format = latestFrameFormat; version = latestFrameVersion; target = stream; w = cameraWidth; h = cameraHeight; }
        if (!firstSendStateLogged)
        {
            firstSendStateLogged = true;
            Log("FIRST_SEND_STATE frame=" + (frame != null) + " stream=" + (target != null) + " client=" + (client != null) + " connected=" + (client != null && client.Connected));
        }
        if (frame == null || target == null || client == null || !client.Connected || version == 0 || version == lastSentFrameVersion) return;
        if (!firstFrameSentLogged)
        {
            firstFrameSentLogged = true;
            Log("FIRST_FRAME_SEND " + w + "x" + h + " format=" + (format == 1 ? "MJPEG" : "RGB24") + " bytes=" + frame.Length);
        }
        byte[] packet = new byte[16 + frame.Length];
        Buffer.BlockCopy(BitConverter.GetBytes(IPAddress.HostToNetworkOrder(frame.Length)), 0, packet, 0, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(IPAddress.HostToNetworkOrder(w)), 0, packet, 4, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(IPAddress.HostToNetworkOrder(h)), 0, packet, 8, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(IPAddress.HostToNetworkOrder(format)), 0, packet, 12, 4);
        Buffer.BlockCopy(frame, 0, packet, 16, frame.Length); writing = true; lastSentFrameVersion = version;
        try { target.BeginWrite(packet, 0, packet.Length, delegate(IAsyncResult result) { try { target.EndWrite(result); } catch { } finally { writing = false; } }, null); }
        catch { writing = false; lock (frameLock) { if (client != null) client.Close(); client = null; stream = null; lastSentFrameVersion = 0; } }
    }

    private void SenderLoop()
    {
        int interval = Math.Max(15, 1000 / fps);
        while (!stopping)
        {
            SendLatestFrame(null, EventArgs.Empty);
            Thread.Sleep(interval);
        }
    }

    private void OnClosed(object sender, FormClosedEventArgs e)
    {
        stopping = true;
        try { if (listener != null) listener.Stop(); } catch { }
        lock (frameLock) { if (client != null) client.Close(); client = null; stream = null; }
        try { if (captureWindow != IntPtr.Zero) { SendMessage(captureWindow, STOP_CAPTURE, IntPtr.Zero, IntPtr.Zero); SendMessage(captureWindow, PREVIEW, IntPtr.Zero, IntPtr.Zero); SendMessage(captureWindow, DRIVER_DISCONNECT, IntPtr.Zero, IntPtr.Zero); DestroyWindow(captureWindow); } } catch { }
    }

    private void Log(string line) { try { File.AppendAllText(logPath, DateTime.Now.ToString("s") + " " + line + Environment.NewLine); } catch { } }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate IntPtr CaptureCallback(IntPtr hwnd, ref VideoHeader header);
    [StructLayout(LayoutKind.Sequential)] private struct VideoHeader { public IntPtr Data; public uint BufferLength, BytesUsed, TimeCaptured; public IntPtr User; public uint Flags; public IntPtr Reserved1, Reserved2, Reserved3, Reserved4; }
    [StructLayout(LayoutKind.Sequential)] private struct BitmapInfoHeader { public uint Size; public int Width, Height; public ushort Planes, BitCount; public uint Compression, SizeImage; public int XPelsPerMeter, YPelsPerMeter; public uint ClrUsed, ClrImportant; }
    [StructLayout(LayoutKind.Sequential)] private struct CaptureParameters
    {
        public uint RequestMicrosecondsPerFrame;
        public int MakeUserHitOKToCapture;
        public uint PercentDropForError;
        public int Yield;
        public uint IndexSize, ChunkGranularity;
        public int UsingDosMemory;
        public uint NumVideoRequested;
        public int CaptureAudio;
        public uint NumAudioRequested, AbortVirtualKey;
        public int AbortLeftMouse, AbortRightMouse, LimitEnabled;
        public uint TimeLimit;
        public int MciControl, StepMciDevice;
        public uint MciStartTime, MciStopTime;
        public int StepCaptureAt2x;
        public uint StepCaptureAverageFrames, AudioBufferSize;
        public int DisableWriteCache;
        public uint AvStreamMaster;
    }
    [DllImport("avicap32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr capCreateCaptureWindowW(string name, int style, int x, int y, int width, int height, IntPtr parent, int id);
    [DllImport("avicap32.dll", CharSet = CharSet.Unicode, EntryPoint = "capGetDriverDescriptionW")] private static extern bool capGetDriverDescriptionW(ushort index, StringBuilder name, int nameLength, StringBuilder version, int versionLength);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
}
