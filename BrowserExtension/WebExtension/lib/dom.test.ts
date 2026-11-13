// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { generatePasswordFields, generateTargets, isGeneratePasswordField, otpTargets, wantsEmail } from './dom';

// jsdom has no layout; `visible()` needs a non-zero box.
HTMLElement.prototype.getBoundingClientRect = () => new DOMRect(0, 0, 200, 40);

afterEach(() => {
  document.body.innerHTML = '';
});

describe('isGeneratePasswordField (Safari icon gate)', () => {
  it('shows on autocomplete=new-password', () => {
    document.body.innerHTML = '<form><input type="password" autocomplete="new-password"></form>';
    expect(isGeneratePasswordField(document.querySelector<HTMLInputElement>('input')!)).toBe(true);
  });

  it('hides on autocomplete=current-password (ordinary login)', () => {
    document.body.innerHTML =
      '<form><input type="email"><input type="password" autocomplete="current-password"></form>';
    expect(isGeneratePasswordField(document.querySelector<HTMLInputElement>('input[type=password]')!)).toBe(false);
  });

  it('hides on a plain single-password sign-in form', () => {
    document.body.innerHTML = '<form><input name="user"><input type="password" name="pass"></form>';
    expect(isGeneratePasswordField(document.querySelector<HTMLInputElement>('input[type=password]')!)).toBe(false);
  });

  it('on new + confirm, shows on the new password only and pairs the confirm field', () => {
    document.body.innerHTML = '<form><input type="password" name="a"><input type="password" name="b"></form>';
    const [a, b] = [...document.querySelectorAll<HTMLInputElement>('input[type=password]')];
    expect(isGeneratePasswordField(a!)).toBe(true);
    expect(isGeneratePasswordField(b!)).toBe(false);
    expect(generateTargets()).toEqual([{ field: a, confirm: b }]);
  });

  it('on a sign-up pairs the username field (an email field wants an email); never on change-password', () => {
    document.body.innerHTML = `<form><input type="email" name="email"><input type="password" autocomplete="new-password">
      <button type="submit">Sign up</button></form>`;
    const user = document.querySelector<HTMLInputElement>('input[type=email]')!;
    expect(generateTargets()[0]?.username).toBe(user);
    expect(wantsEmail(user)).toBe(true);
    // A reset form makes a password too, but its text field is not the account's name.
    document.body.innerHTML = `<form><h2>Reset your password</h2><input name="code">
      <input type="password" autocomplete="new-password"><input type="password" autocomplete="new-password"></form>`;
    expect(generateTargets()[0]?.username).toBeUndefined();
    document.body.innerHTML = `<form><input name="user">
      <input type="password" autocomplete="current-password"><input type="password" autocomplete="new-password"></form>`;
    expect(generateTargets()[0]?.username).toBeUndefined();
    expect(wantsEmail(document.querySelector<HTMLInputElement>('input[name=user]')!)).toBe(false);
  });

  it('on a change-password form skips the current password', () => {
    document.body.innerHTML = `<form>
      <input type="password" name="current_password">
      <input type="password" name="new_password">
      <input type="password" name="new_password_confirmation"></form>`;
    const [, fresh, confirm] = [...document.querySelectorAll<HTMLInputElement>('input[type=password]')];
    expect(generateTargets()).toEqual([{ field: fresh, confirm }]);
  });

  it('prefers the field marked new-password over a confirm that comes first in the DOM', () => {
    document.body.innerHTML = `<form>
      <input type="password" name="password_confirm" autocomplete="new-password">
      <input type="password" name="password" autocomplete="new-password"></form>`;
    const [confirm, fresh] = [...document.querySelectorAll<HTMLInputElement>('input[type=password]')];
    expect(generateTargets()[0]!.field).toBe(fresh);
    expect(isGeneratePasswordField(confirm!)).toBe(false);
  });

  it('hides on a login form that also has a Sign up and Forgot password button (Cloudflare-like)', () => {
    document.body.innerHTML = `<form><h1>Get started with your account</h1>
      <input type="email" name="email"><input type="password" name="password">
      <button type="button">Forgot your password?</button>
      <button type="submit">Log in</button>
      <button type="button">Sign up</button></form>`;
    expect(generatePasswordFields()).toHaveLength(0);
  });

  it('shows on a single-password sign-up with no <form> (SPA)', () => {
    document.body.innerHTML = `<div><h2>Create your account</h2>
      <input type="email"><input type="password" name="pw">
      <button type="button">Create account</button>
      <button type="button">Already have an account? Log in</button></div>`;
    expect(generatePasswordFields()).toHaveLength(1);
  });

  it('hides on a single-password SPA sign-in with no <form>', () => {
    document.body.innerHTML = '<div><input type="email"><input type="password"><button>Sign in</button></div>';
    expect(generatePasswordFields()).toHaveLength(0);
  });

  it('shows when labels say change password / sign up', () => {
    document.body.innerHTML = '<form><h2>Create account</h2><input type="password" name="pass"></form>';
    expect(isGeneratePasswordField(document.querySelector<HTMLInputElement>('input[type=password]')!)).toBe(true);
  });

  it('generatePasswordFields returns only generate-relevant inputs', () => {
    document.body.innerHTML = `
      <form id="login"><input type="password" autocomplete="current-password"></form>
      <form id="reg"><input type="password" autocomplete="new-password"></form>`;
    const found = generatePasswordFields();
    expect(found).toHaveLength(1);
    expect(found[0]!.autocomplete).toBe('new-password');
  });
});

describe('otpTargets', () => {
  it('ignores a login form plus a paste-check field (issue #209 test page)', () => {
    document.body.innerHTML = `<form>
      <label for="user">Username</label>
      <input id="user" name="username" autocomplete="username" />
      <label for="pass">Password</label>
      <input id="pass" name="password" type="password" autocomplete="current-password" />
    </form>
    <label for="paste">Paste clipboard here</label>
    <input id="paste" placeholder="Cmd+V after fill" />`;
    expect(otpTargets()).toEqual([]);
  });

  it('finds autocomplete=one-time-code', () => {
    document.body.innerHTML = '<form><input id="code" autocomplete="one-time-code"></form>';
    expect(otpTargets()).toHaveLength(1);
    expect(otpTargets()[0]![0]!.id).toBe('code');
  });
});
