using System.Text.Json.Serialization;

namespace Tailblaze.Models;

public sealed record CoworkTask
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("description")]
    public string Description { get; init; } = "";

    [JsonPropertyName("status")]
    public string Status { get; init; } = "pending";

    [JsonPropertyName("result")]
    public string? Result { get; init; }

    [JsonPropertyName("createdAt")]
    public DateTimeOffset? CreatedAt { get; init; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset? UpdatedAt { get; init; }

    public string StatusIcon => Status switch
    {
        "pending" => "+",
        "running" => ">",
        "completed" => "✓",
        "failed" => "!",
        _ => "?"
    };

    public string DisplayLine => $"[{StatusIcon}] {Title}";

    public string ShortId => Id.Length > 8 ? Id[..8] : Id;
}
