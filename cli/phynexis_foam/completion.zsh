# Zsh tab completion for the phynexis-foam CLI.
# Pip install registers share/zsh/site-functions/_phynexis-foam automatically.
# Optional:
#   eval "$(phynexis-foam completion zsh)"

source "${0:A:h}/_phynexis-foam"
autoload -Uz compdef
compdef _phynexis-foam phynexis-foam
