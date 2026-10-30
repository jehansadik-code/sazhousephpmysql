(() => {
  'use strict';
  const requestForm = document.getElementById('password-reset-request-form');
  const confirmForm = document.getElementById('password-reset-confirm-form');
  const notice = document.getElementById('reset-notice');
  const copy = document.getElementById('reset-copy');
  const params = new URLSearchParams(location.hash.slice(1));
  const selector = params.get('selector') || '';
  const token = params.get('token') || '';
  const hasLink = /^[a-f0-9]{32}$/.test(selector) && /^[a-f0-9]{64}$/.test(token);
  const message = text => { notice.textContent = text; };
  if (hasLink) {
    requestForm.hidden = true;
    confirmForm.hidden = false;
    copy.textContent = 'Choose a new password. This link expires shortly and can be used once.';
  }
  requestForm.addEventListener('submit', async event => {
    event.preventDefault();
    const button = requestForm.querySelector('button');
    button.disabled = true;
    const result = await window.SAZ_API.requestPasswordReset(new FormData(requestForm).get('email'));
    button.disabled = false;
    message(result.error || 'If an account exists, a reset link has been sent.');
  });
  confirmForm.addEventListener('submit', async event => {
    event.preventDefault();
    const data = new FormData(confirmForm);
    if (data.get('password') !== data.get('confirmPassword')) return message('The passwords do not match.');
    const button = confirmForm.querySelector('button');
    button.disabled = true;
    const result = await window.SAZ_API.confirmPasswordReset(selector, token, data.get('password'));
    button.disabled = false;
    if (result.error) return message(result.error);
    history.replaceState(null, '', 'reset-password.html');
    confirmForm.hidden = true;
    message('Your password was reset. You can now sign in.');
  });
})();
