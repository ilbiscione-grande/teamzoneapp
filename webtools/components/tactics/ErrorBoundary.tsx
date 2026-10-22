"use client";

// A failure in one part of the editor stays there: the part shows what
// went wrong (so it can be told on), and can be tried again, while the rest
// keeps working. Nothing of the project is lost; it is saved as it goes.
import { Component, type ReactNode } from "react";

type Props = { label: string; children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack?: string | null }) {
    console.error(`Tacticsboard: ${this.props.label}`, error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="tb-error" role="alert">
        <strong>{this.props.label} kunde inte visas.</strong>
        <code>{error.name}: {error.message}</code>
        <code className="tb-error-stack">{(error.stack ?? "").split("\n").slice(1, 4).join("\n")}</code>
        <div className="tb-actions">
          <button type="button" className="wt-button small" onClick={() => this.setState({ error: null })}>Försök igen</button>
          <button type="button" className="wt-button secondary small" onClick={() => window.location.reload()}>Ladda om sidan</button>
        </div>
      </div>
    );
  }
}
