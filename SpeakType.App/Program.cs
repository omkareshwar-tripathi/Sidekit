namespace SpeakType.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Brick 0 establishes only the scaffold. The system-tray UI, global
        // hotkey, audio capture, transcription, and paste pipeline arrive in
        // later bricks (see BRICKS.md).
        ApplicationConfiguration.Initialize();
    }
}
