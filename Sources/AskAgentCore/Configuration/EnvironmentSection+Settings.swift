// The environment settings (ADR-0106), each declared once (roadmap 0209). Both lists add up across layers: what one layer withholds,
// a later one cannot give back by leaving it out.
extension EnvironmentSection: DeclaredSection {
    static let settings = SettingTable<EnvironmentSection>(
        "environment",
        [
            .adds(
                SettingCatalog.row(
                    "environment.withhold",
                    .structured,
                    #"["AWS_*"]"#,
                    "ask's and well-known credential variables",
                    "More variables kept from commands."
                ),
                \.withhold,
                sorted: true
            ),
            .adds(
                SettingCatalog.row(
                    "environment.pass",
                    .structured,
                    #"["GH_TOKEN"]"#,
                    "none",
                    user: true,
                    "Withheld variables commands get anyway."
                ),
                \.pass,
                sorted: true
            ),
            .string(
                SettingCatalog.row(
                    "environment.shell",
                    .text,
                    #""zsh""#,
                    "the first bash on your PATH, else /bin/bash, else ksh, sh or dash, else your login shell",
                    user: true,
                    "The shell commands run in."
                ),
                \.shell
            )
        ]
    )
}
