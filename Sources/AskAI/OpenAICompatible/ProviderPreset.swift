/// An OpenAI-compatible service ask knows by name, so it needs no `providers.json` entry (roadmap 0034).
///
/// Names, endpoints and key variables are pi's, so one environment serves both. Each endpoint answered a keyless
/// chat request as an API that wants a key (diary 18); a service that could not be verified is left out until it can.
struct ProviderPreset: Sendable, Equatable {
    /// The name `--provider` and `providers.json` use.
    let name: String
    /// Where chat completions are served, without a trailing slash.
    let baseURL: String
    /// The environment variable that holds the key.
    let keyVariable: String

    /// Every preset, in name order.
    // @dl:accept -- a table of data: its rows repeat their shape by being rows, and a loop over a second table would hide it
    static let all: [ProviderPreset] = [
        // @dl:accept -- the rows are data, and four of them differ only in a region name
        ProviderPreset("baseten", "https://inference.baseten.co/v1", "BASETEN_API_KEY"),
        ProviderPreset("cerebras", "https://api.cerebras.ai/v1", "CEREBRAS_API_KEY"),
        ProviderPreset("deepseek", "https://api.deepseek.com", "DEEPSEEK_API_KEY"),
        ProviderPreset("fireworks", "https://api.fireworks.ai/inference/v1", "FIREWORKS_API_KEY"),
        ProviderPreset("google", "https://generativelanguage.googleapis.com/v1beta/openai", "GEMINI_API_KEY"),
        ProviderPreset("groq", "https://api.groq.com/openai/v1", "GROQ_API_KEY"),
        ProviderPreset("huggingface", "https://router.huggingface.co/v1", "HF_TOKEN"),
        ProviderPreset("kimi-coding", "https://api.kimi.com/coding/v1", "KIMI_API_KEY"),
        ProviderPreset("mistral", "https://api.mistral.ai/v1", "MISTRAL_API_KEY"),
        ProviderPreset("moonshotai", "https://api.moonshot.ai/v1", "MOONSHOT_API_KEY"),
        ProviderPreset("moonshotai-cn", "https://api.moonshot.cn/v1", "MOONSHOT_API_KEY"),
        ProviderPreset("nvidia", "https://integrate.api.nvidia.com/v1", "NVIDIA_API_KEY"),
        ProviderPreset("openai", "https://api.openai.com/v1", "OPENAI_API_KEY"),
        ProviderPreset("openrouter", "https://openrouter.ai/api/v1", "OPENROUTER_API_KEY"),
        ProviderPreset(
            "qwen-token-plan", "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
            "QWEN_TOKEN_PLAN_API_KEY"),
        ProviderPreset(
            "qwen-token-plan-cn", "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
            "QWEN_TOKEN_PLAN_CN_API_KEY"),
        ProviderPreset("together", "https://api.together.ai/v1", "TOGETHER_API_KEY"),
        ProviderPreset("xai", "https://api.x.ai/v1", "XAI_API_KEY"),
        ProviderPreset("xiaomi", "https://api.xiaomimimo.com/v1", "XIAOMI_API_KEY"),
        ProviderPreset(
            "xiaomi-token-plan-ams", "https://token-plan-ams.xiaomimimo.com/v1", "XIAOMI_TOKEN_PLAN_AMS_API_KEY"),
        ProviderPreset(
            "xiaomi-token-plan-cn", "https://token-plan-cn.xiaomimimo.com/v1", "XIAOMI_TOKEN_PLAN_CN_API_KEY"),
        ProviderPreset(
            "xiaomi-token-plan-sgp", "https://token-plan-sgp.xiaomimimo.com/v1", "XIAOMI_TOKEN_PLAN_SGP_API_KEY"),
        ProviderPreset("zai", "https://api.z.ai/api/coding/paas/v4", "ZAI_API_KEY"),
        ProviderPreset("zai-coding-cn", "https://open.bigmodel.cn/api/coding/paas/v4", "ZAI_CODING_CN_API_KEY")
    ]

    /// The preset named `name`, if there is one.
    static func named(_ name: String) -> ProviderPreset? { all.first { $0.name == name } }

    private init(_ name: String, _ baseURL: String, _ keyVariable: String) {
        self.name = name
        self.baseURL = baseURL
        self.keyVariable = keyVariable
    }
}
