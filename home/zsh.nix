{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    defaultKeymap = "emacs";

    history = {
      append = true;
      expireDuplicatesFirst = true;
      extended = true;
      findNoDups = true;
      ignoreAllDups = true;
      ignoreDups = true;
      ignoreSpace = true;
      save = 100000;
      saveNoDups = true;
      share = true;
      size = 100000;
    };

    setOptions = [
      "COMPLETE_IN_WORD"
      "HIST_REDUCE_BLANKS"
    ];

    shellAliases = {
      l = "ls -lh";
      la = "ls -lAh";
      ll = "ls -lah";
      dmesg = "dmesg --color=always";
      ip = "ip -color=auto";
      reset = "reset; exec zsh";
    };

    initContent = ''
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

      [[ -r "$HOME/.config/zsh/secrets.zsh" ]] && source "$HOME/.config/zsh/secrets.zsh"

      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^X^E' edit-command-line

      bindkey -M emacs $'\e[1;5D' backward-word
      bindkey -M emacs $'\e[5D' backward-word
      bindkey -M emacs $'\e[1;5C' forward-word
      bindkey -M emacs $'\e[5C' forward-word

      if zmodload zsh/terminfo 2>/dev/null; then
        [[ -n "''${terminfo[kpp]}" ]] && bindkey -M emacs "''${terminfo[kpp]}" up-line-or-history
        [[ -n "''${terminfo[knp]}" ]] && bindkey -M emacs "''${terminfo[knp]}" down-line-or-history
        [[ -n "''${terminfo[kcbt]}" ]] && bindkey -M emacs "''${terminfo[kcbt]}" reverse-menu-complete
        [[ -n "''${terminfo[kdch1]}" ]] && bindkey -M emacs "''${terminfo[kdch1]}" delete-char
        [[ -n "''${terminfo[khome]}" ]] && bindkey -M emacs "''${terminfo[khome]}" beginning-of-line
        [[ -n "''${terminfo[kend]}" ]] && bindkey -M emacs "''${terminfo[kend]}" end-of-line
      fi

      bindkey -M emacs $'\e[3~' delete-char

      for key in $'\e[H' $'\eOH' $'\e[1~'; do
        bindkey -M emacs "$key" beginning-of-line
      done
      for key in $'\e[F' $'\eOF' $'\e[4~'; do
        bindkey -M emacs "$key" end-of-line
      done

      sudo-command-line() {
        [[ -z $BUFFER ]] && zle up-history
        if [[ $BUFFER == sudo\ * ]]; then
          BUFFER=''${BUFFER#sudo }
          (( CURSOR = CURSOR > 5 ? CURSOR - 5 : 0 ))
        else
          BUFFER="sudo $BUFFER"
          (( CURSOR += 5 ))
        fi
      }
      zle -N sudo-command-line
      bindkey '\e\e' sudo-command-line
    '';
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = false;
    settings = {
      add_newline = false;
      format = "$username$hostname$directory$git_branch$status$time$character";

      username = {
        show_always = true;
        format = "[$user]($style)@";
        style_user = "bold blue";
      };
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "bold blue";
      };
      directory = {
        format = "[$path]($style) ";
        style = "bold cyan";
        truncation_length = 3;
      };
      git_branch = {
        format = "[$symbol$branch]($style) ";
        symbol = "git:";
        style = "bold green";
      };
      status = {
        disabled = false;
        format = "[$status]($style) ";
        style = "bold red";
      };
      time = {
        disabled = false;
        format = "[$time]($style) ";
        style = "dimmed white";
        time_format = "%H:%M";
      };
      character = {
        success_symbol = "[%](bold green)";
        error_symbol = "[%](bold red)";
      };
    };
  };
}
