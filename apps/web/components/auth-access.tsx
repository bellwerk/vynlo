"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { KeyRound, Mail, ShieldCheck } from "lucide-react";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { getBrowserSupabase } from "../lib/supabase-browser";
import {
  acceptWorkspaceInvitationSession,
  workspaceInvitationLoginRedirect,
  type WorkspaceInvitationContext,
} from "../lib/workspace-invitation-client";

export interface AuthAccessCopy {
  readonly configurationError: string;
  readonly emailLabel: string;
  readonly genericError: string;
  readonly invalidInvitationLink: string;
  readonly invitationAcceptError: string;
  readonly invitationAccepting: string;
  readonly invitationNote: string;
  readonly magicLinkAction: string;
  readonly magicLinkSent: string;
  readonly passwordAction: string;
  readonly passwordHint: string;
  readonly passwordLabel: string;
  readonly sessionFound: string;
  readonly working: string;
}

interface AuthAccessProps {
  readonly copy: AuthAccessCopy;
  readonly hasInvalidInvitationContext?: boolean;
  readonly invitation?: WorkspaceInvitationContext;
}

export function AuthAccess({
  copy,
  hasInvalidInvitationContext = false,
  invitation,
}: Readonly<AuthAccessProps>) {
  const router = useRouter();
  const transitionInFlight = useRef(false);
  const [busy, setBusy] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [status, setStatus] = useState<string | null>(
    hasInvalidInvitationContext ? copy.invalidInvitationLink : null,
  );
  const [configured, setConfigured] = useState(true);

  const continueWithSession = useCallback(
    async (session: Session) => {
      if (transitionInFlight.current) {
        return;
      }
      transitionInFlight.current = true;

      if (!invitation) {
        setStatus(copy.sessionFound);
        router.replace("/operations");
        return;
      }

      setBusy(true);
      setStatus(copy.invitationAccepting);
      try {
        await acceptWorkspaceInvitationSession({
          accessToken: session.access_token,
          context: invitation,
        });
        router.replace("/operations");
      } catch {
        transitionInFlight.current = false;
        setBusy(false);
        setStatus(copy.invitationAcceptError);
      }
    },
    [
      copy.invitationAcceptError,
      copy.invitationAccepting,
      copy.sessionFound,
      invitation,
      router,
    ],
  );

  useEffect(() => {
    try {
      const client = getBrowserSupabase();
      void client.auth.getSession().then(({ data }) => {
        if (data.session) {
          void continueWithSession(data.session);
        }
      });
      const { data } = client.auth.onAuthStateChange((event, session) => {
        if ((event === "SIGNED_IN" || event === "TOKEN_REFRESHED") && session) {
          void continueWithSession(session);
        }
      });
      return () => data.subscription.unsubscribe();
    } catch {
      queueMicrotask(() => {
        setConfigured(false);
        setStatus(
          hasInvalidInvitationContext
            ? copy.invalidInvitationLink
            : copy.configurationError,
        );
      });
    }
  }, [
    continueWithSession,
    copy.configurationError,
    copy.invalidInvitationLink,
    hasInvalidInvitationContext,
  ]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setStatus(null);

    try {
      const client = getBrowserSupabase();
      const normalizedEmail = email.trim().toLowerCase();
      const result = password
        ? await client.auth.signInWithPassword({
            email: normalizedEmail,
            password,
          })
        : await client.auth.signInWithOtp({
            email: normalizedEmail,
            options: {
              emailRedirectTo: (() => {
                if (invitation) {
                  return workspaceInvitationLoginRedirect(
                    window.location.origin,
                    invitation,
                  );
                }
                return new URL("/login", window.location.origin).toString();
              })(),
              shouldCreateUser: false,
            },
          });

      if (result.error) {
        setStatus(copy.genericError);
      } else if (password && result.data.session) {
        await continueWithSession(result.data.session);
      } else {
        setStatus(copy.magicLinkSent);
      }
    } catch {
      setStatus(copy.genericError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="auth-form" onSubmit={submit}>
      <div className="auth-assurance">
        <ShieldCheck aria-hidden="true" size={19} />
        <p>{copy.invitationNote}</p>
      </div>

      <label>
        <span>{copy.emailLabel}</span>
        <span className="field-with-icon">
          <Mail aria-hidden="true" size={18} />
          <input
            autoComplete="email"
            disabled={!configured || busy}
            inputMode="email"
            maxLength={254}
            name="email"
            onChange={(event) => setEmail(event.target.value)}
            required
            type="email"
            value={email}
          />
        </span>
      </label>

      <label>
        <span>{copy.passwordLabel}</span>
        <span className="field-with-icon">
          <KeyRound aria-hidden="true" size={18} />
          <input
            autoComplete="current-password"
            disabled={!configured || busy}
            maxLength={200}
            name="password"
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            value={password}
          />
        </span>
        <small>{copy.passwordHint}</small>
      </label>

      <Button disabled={!configured || busy} type="submit">
        {busy
          ? copy.working
          : password
            ? copy.passwordAction
            : copy.magicLinkAction}
      </Button>

      <p aria-live="polite" className="form-status" role="status">
        {status}
      </p>
    </form>
  );
}
