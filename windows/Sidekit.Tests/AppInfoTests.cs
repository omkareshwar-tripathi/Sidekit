using Sidekit.Core;

namespace Sidekit.Tests;

public class AppInfoTests
{
    [Fact]
    public void Name_is_Sidekit() => Assert.Equal("Sidekit", AppInfo.Name);
}
