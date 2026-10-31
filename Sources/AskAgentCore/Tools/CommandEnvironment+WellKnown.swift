extension CommandEnvironment {
    /// Credential variables common tools and services read, withheld from commands by default (roadmap 0153): a token a command prints goes
    /// to the model and on to its provider. Exact names only, each one a secret by its name, so a tool's ordinary settings (`AWS_REGION`,
    /// `GITHUB_ACTIONS`, `NPM_CONFIG_PREFIX`) still reach it. `environment.pass` lets one back in.
    public static let wellKnownCredentials: Set<String> = [
        // Source hosts.
        "GITHUB_TOKEN", "GH_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN", "GITLAB_TOKEN", "GL_TOKEN",
        // Cloud providers.
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_SECURITY_TOKEN", "AZURE_CLIENT_SECRET",
        "ARM_CLIENT_SECRET", "DIGITALOCEAN_ACCESS_TOKEN", "HEROKU_API_KEY", "VERCEL_TOKEN", "NETLIFY_AUTH_TOKEN",
        "CLOUDFLARE_API_TOKEN", "CF_API_TOKEN",
        // Model providers ask may not be configured for.
        "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "MISTRAL_API_KEY", "GROQ_API_KEY", "XAI_API_KEY",
        "OPENROUTER_API_KEY", "DEEPSEEK_API_KEY", "HF_TOKEN", "HUGGING_FACE_HUB_TOKEN",
        // Package registries.
        "NPM_TOKEN", "NODE_AUTH_TOKEN", "PYPI_TOKEN", "TWINE_PASSWORD", "CARGO_REGISTRY_TOKEN", "DOCKER_PASSWORD",
        "DOCKERHUB_TOKEN",
        // Services.
        "SLACK_TOKEN", "SLACK_BOT_TOKEN", "STRIPE_SECRET_KEY", "SENTRY_AUTH_TOKEN"
    ]
}
