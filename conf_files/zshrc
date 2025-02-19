source ~/antigen.zsh
antigen use oh-my-zsh
antigen bundle git
antigen bundle pip
antigen bundle command-not-found
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle colored-man-pages
antigen bundle colorize
antigen bundle cp
antigen bundle web-search
antigen bundle virtualenv
antigen bundle virtualenvwrapper
antigen theme eendroroy/alien alien

antigen apply
setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'


# sources
source /usr/share/doc/fzf/examples/key-bindings.zsh
source /usr/share/doc/fzf/examples/completion.zsh
source /usr/share/autojump/autojump.sh
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source /home/greg/.local/bin/virtualenvwrapper.sh

# visual configs
export EDITOR=vim
export VISUAL=vim
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
export FZF_CTRL_T_OPTS="--preview 'batcat -n --color=always --line-range :500 {}'"

# tools config
export WORKON_HOME=~/Envs
export PATH=$PATH:/home/greg/src/configs/scripts
export PATH=$PATH:/home/greg/programy/pycharm-community-2024.3.2/bin

# aliases
alias here='a="cp -R "; a+=`xclip -selection clipboard -o`; a+=" ."; eval $a'
alias catc='colorize'

