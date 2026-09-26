import { LoginForm } from "./login-form";
import { ThemeToggle } from "./theme-toggle";

export default function LoginPage() {
  return <>
    <ThemeToggle />
    <main className="auth-wrap auth-welcome">
      <div className="auth-particles" aria-hidden="true" />
      <section className="auth-layout anim-in">
        <div className="auth-intro">
          <div className="auth-logo-stage">
            <img className="auth-logo" src="/icons/icon.png" alt="EduFlow" />
            <span className="auth-orbit auth-orbit-one"><span className="auth-electron-track" /></span>
            <span className="auth-orbit auth-orbit-two"><span className="auth-electron-track" /></span>
          </div>
        </div>
        <LoginForm />
      </section>
    </main>
  </>;
}
