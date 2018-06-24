{ config, lib, ... }:

with lib;

let

  cfg = config.mail;
  dag = config.lib.dag;
  mail = config.lib.mail;

  tlsModule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable TLS/SSL.
        '';
      };

      useStartTls = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to use STARTTLS.
        '';
      };

      certificatesFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to file containing certificate authorities that should
          be used to validate the connection authenticity. If
          <literal>null</literal> then the system default is used.
          Note, if set then the system default may still be accepted.
        '';
      };
    };
  };

  imapModule = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        example = "imap.example.org";
        description = ''
          Hostname of IMAP server.
        '';
      };

      port = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 993;
        description = ''
          The port on which the IMAP server listens. If
          <literal>null</literal> then the default port is used.
        '';
      };

      tls = mkOption {
        type = tlsModule;
        default = {};
        description = ''
          Configuration for secure connections.
        '';
      };
    };
  };

  smtpModule = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        example = "smtp.example.org";
        description = ''
          Hostname of SMTP server.
        '';
      };

      port = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 465;
        description = ''
          The port on which the SMTP server listens. If
          <literal>null</literal> then the default port is used.
        '';
      };

      tls = mkOption {
        type = tlsModule;
        default = {};
        description = ''
          Configuration for secure connections.
        '';
      };
    };
  };

  maildirModule = types.submodule {
    options = {
      path = mkOption {
        type = types.nullOr types.path;
        defaultText = "$MAILDIR/\${name}";
        description = ''
          Path to Maildir directory where mail for this account is
          stored.
        '';
      };
    };
  };

  # gpgModule = types.submodule {
  # };

  mailAccount = types.submodule ({ name, config, ... }: {
    options = {
      # should be unque across mailAccounts => use it as key ?
      # but it is used
      name = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          Unique identifier of the account. This is set to the
          attribute name of the account configuration.
        '';
      };

      flavor = mkOption {
        type = types.enum [ "standard" "runbox.com" ];
        default = "standard";
        description = ''
          Some email providers have peculiar behavior that require
          special treatment. This option is therefore intended to
          indicate the nature of the provider.
          </para><para>
          When this indicates a specific provider then the IMAP and
          SMTP server configuration may be set automatically.
        '';
      };

      address = mkOption {
        type = types.strMatching "@";
        example = "me@example.org";
        description = "The email address of this account.";
      };

      realName = mkOption {
        type = types.str;
        example = "Jane Doe";
        description = "Name displayed when sending mails.";
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The server username of this account. This will be used as
          the SMTP and IMAP user name.
        '';
      };

      passwordCommand = mkOption {
        type = types.nullOr (types.either types.str (types.listOf types.str));
        default = null;
        apply = p: if isString p then splitString " " p else p;
        example = [ "secret-tool" "lookup" "email" "me@example.org" ];
        description = ''
          A command, which when run writes the account password on
          standard output.
        '';
      };

      imap = mkOption {
        type = types.nullOr imapModule;
        default = null;
        description = ''
          The IMAP configuration to use for this account.
        '';
      };

      smtp = mkOption {
        type = types.nullOr smtpModule;
        default = null;
        description = ''
          The SMTP configuration to use for this account.
        '';
      };

      maildir = mkOption {
        type = types.nullOr maildirModule;
        default = null;
        description = ''
          Path to Maildir directory where mail for this account is
          stored.
        '';
      };

      postSyncHook = mkOption {
        default = types.lines;
        description = "Commands to run after performing a sync.";
      };
    };

    config = mkMerge [
      {
        name = name;

        maildir.path = mkOptionDefault "${cfg.maildir}/${name}";

        # imap.userName = mkIf (!config.userName) (
        #   mkOptionDefault config.userName
        # );

        # imap.passwordCommand = mkIf (!config.passwordCommand) (
        #   mkOptionDefault config.passwordCommand
        # );
      }

      (mkIf (config.flavor == "runbox.com") {
        imap = {
          host = "mail.runbox.com";
        };

        smtp = {
          host = "mail.runbox.com";
        };
      })
    ];
  });

in

{
  options.mail = {
    enable = mkEnableOption "email account management";

    maildir = mkOption {
      type = types.path;
      default = config.home.homeDirectory + "/Maildir";
      defaultText = "$HOME/Maildir";
      description = ''
        The base directory for account maildir directories.
      '';
    };

    accounts = mkOption {
      type = types.attrsOf mailAccount;
      default = {};
      example = literalExample ''
        {
          name = "gmail";
          userName = "Luke";
          realname = "Luke skywalker";
          address = "luke.skywalker@gmail.com";
          sendHost = "smtp.gmail.com";
          contactCompletion = "notmuch address";
        }'';
      description = "List your email accounts.";
    };

    certificateStore = mkOption {
      type = types.path;
      default =  "/etc/ssl/certs/ca-certificates.crt";
      description = ''
        Path towards the certificates files.
      '';
    };

    generateShellAliases = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Generate one shell alias per (program/account). For instance, if alot is enabled and an account is defined with name gmail, then it will generate alot-gmail
      '';
    };
  };

  # TODO assert on an unset store ?
  config = mkMerge [
    (mkIf cfg.enable {
      home.sessionVariables.MAILDIR = cfg.maildir;

      # todo check mta/mua creation process
      home.activation.createMailStores =
        dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
          mkdir -p ${concatMapSep " " (getAttr "maildirPath") cfg.accounts}
        '';
    })

    {
      home.file."MAILACC".text =
        concatStringsSep "\n"
        (mapAttrsToList (v: a: ''
          ${a.name}:
            ${a.userName}
            ${concatStringsSep "," a.passwordCommand}
            ${builtins.toXML a.imap}
        '') cfg.accounts);
    }
  ];
}
