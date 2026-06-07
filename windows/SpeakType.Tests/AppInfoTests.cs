using SpeakType.Core;

namespace SpeakType.Tests;

public class AppInfoTests
{
    [Fact]
    public void Name_is_SpeakType() => Assert.Equal("SpeakType", AppInfo.Name);
}
