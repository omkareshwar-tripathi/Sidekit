using Sidekit.Core.Models;
using Sidekit.Core.Settings;

namespace Sidekit.Tests.Models;

public sealed class ModelCatalogTests
{
    [Fact]
    public void Resolve_returns_a_known_model_name_unchanged()
    {
        Assert.Equal("small.en", ModelCatalog.Resolve("small.en"));
    }

    [Fact]
    public void Resolve_matches_known_models_case_insensitively()
    {
        // The catalog is OrdinalIgnoreCase, so a differently-cased known name is kept as typed
        // (the store re-resolves it to the canonical filename later).
        Assert.Equal("BASE.EN", ModelCatalog.Resolve("BASE.EN"));
    }

    [Fact]
    public void Resolve_falls_back_to_the_default_for_an_unknown_model()
    {
        Assert.Equal(AppSettings.DefaultModelSize, ModelCatalog.Resolve("not-a-real-model"));
    }

    [Fact]
    public void Resolve_falls_back_to_the_default_for_null()
    {
        Assert.Equal(AppSettings.DefaultModelSize, ModelCatalog.Resolve(null));
    }
}
