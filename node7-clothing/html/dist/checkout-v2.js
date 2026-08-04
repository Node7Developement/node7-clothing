(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'node7-clothing';

    let panel = null;
    let statusNode = null;
    let paymentButtons = [];
    let open = false;

    const post = async (endpoint, payload = {}) => {
        try {
            const response = await fetch(`https://${RESOURCE}/${endpoint}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(payload)
            });
            return await response.json().catch(() => ({}));
        } catch (error) {
            return { ok: false, message: 'The tailor could not process that request.' };
        }
    };

    const installUiFixes = () => {
        if (document.getElementById('node7-clothing-runtime-fixes')) return;

        const style = document.createElement('style');
        style.id = 'node7-clothing-runtime-fixes';
        style.textContent = `
            html, body, #root, #App, #MainContent {
                overflow-x: hidden !important;
            }

            /* Keep every QBR slider track inside its own control row. */
            #MainContent .skinControls {
                position: relative !important;
                overflow: hidden !important;
                contain: layout paint !important;
            }

            #MainContent .skinControls .rc-slider {
                position: relative !important;
                width: 70% !important;
                max-width: 70% !important;
                flex: 0 0 70% !important;
                overflow: hidden !important;
            }

            .rc-slider-track {
                display: none !important;
                max-width: 100% !important;
            }

            .rc-slider > .rc-slider-track {
                display: block !important;
            }

            body > .rc-slider-track,
            #root > .rc-slider-track,
            #App > .rc-slider-track,
            #MainContent > .rc-slider-track {
                display: none !important;
            }

            #node7-checkout-panel {
                position: fixed;
                inset: 0;
                z-index: 2147483646;
                display: none;
                align-items: center;
                justify-content: center;
                pointer-events: none;
                background: transparent;
            }

            #node7-checkout-panel.is-visible {
                display: flex;
            }

            .node7-checkout-card {
                width: 360px;
                box-sizing: border-box;
                padding: 24px;
                pointer-events: auto;
                color: #f0e6cf;
                text-align: center;
                font-family: "RDR Lino", Georgia, serif;
                border: 2px solid #efe8d6;
                outline: 5px solid rgba(0, 0, 0, 0.92);
                background: rgba(13, 13, 13, 0.98);
                box-shadow: 0 20px 65px rgba(0, 0, 0, 0.72);
            }

            .node7-checkout-kicker {
                margin: 0;
                color: #cfc4aa;
                font-size: 13px;
                letter-spacing: 0.16em;
                text-transform: uppercase;
            }

            .node7-checkout-card h2 {
                margin: 8px 0 6px;
                color: #fff;
                font-size: 30px;
                font-weight: 500;
                text-transform: uppercase;
            }

            #node7-checkout-summary {
                margin: 0 0 18px;
                color: #d9d1c0;
                font-size: 18px;
            }

            .node7-checkout-actions {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 12px;
            }

            .node7-checkout-card button {
                min-height: 46px;
                border: 1px solid rgba(255, 255, 255, 0.72);
                border-radius: 4px;
                background: #d31414;
                color: #fff;
                font: inherit;
                font-size: 18px;
                text-transform: uppercase;
                cursor: pointer;
            }

            .node7-checkout-card button:hover:not(:disabled) {
                background: #a50f0f;
            }

            .node7-checkout-card button:disabled {
                opacity: 0.55;
                cursor: wait;
            }

            #node7-checkout-cancel {
                width: 100%;
                margin-top: 12px;
                background: #3b3b3b;
            }

            #node7-checkout-status {
                min-height: 20px;
                margin: 12px 0 0;
                color: #f2d28f;
                font-size: 15px;
            }
        `;
        document.head.appendChild(style);
    };

    const ensurePanel = () => {
        installUiFixes();
        if (panel) return;

        panel = document.createElement('section');
        panel.id = 'node7-checkout-panel';
        panel.setAttribute('aria-hidden', 'true');
        panel.innerHTML = `
            <div class="node7-checkout-card" role="dialog" aria-modal="true" aria-labelledby="node7-checkout-title">
                <p class="node7-checkout-kicker">NODE7 Tailor</p>
                <h2 id="node7-checkout-title">Confirm Purchase</h2>
                <p id="node7-checkout-summary">Choose a payment method.</p>
                <div class="node7-checkout-actions">
                    <button type="button" data-payment-method="cash">Pay Cash</button>
                    <button type="button" data-payment-method="bank">Pay Bank</button>
                </div>
                <button type="button" id="node7-checkout-cancel">Back</button>
                <p id="node7-checkout-status" role="status"></p>
            </div>
        `;
        document.body.appendChild(panel);

        statusNode = panel.querySelector('#node7-checkout-status');
        paymentButtons = Array.from(panel.querySelectorAll('[data-payment-method]'));

        paymentButtons.forEach((button) => {
            button.addEventListener('click', async () => {
                if (!open || button.disabled) return;

                paymentButtons.forEach((entry) => { entry.disabled = true; });
                panel.querySelector('#node7-checkout-cancel').disabled = true;
                statusNode.textContent = `Confirming ${button.textContent.toLowerCase()}…`;

                const result = await post('purchase', {
                    method: button.dataset.paymentMethod
                });

                if (!result.ok) {
                    statusNode.textContent = result.message || 'The payment request failed.';
                    paymentButtons.forEach((entry) => { entry.disabled = false; });
                    panel.querySelector('#node7-checkout-cancel').disabled = false;
                }
            });
        });

        panel.querySelector('#node7-checkout-cancel').addEventListener('click', async () => {
            if (!open) return;
            const result = await post('cancelPayment');
            if (result.ok) hide();
        });
    };

    const show = (data) => {
        ensurePanel();

        const total = Number(data.total || 0);
        const changed = Number(data.changed || 0);
        const methods = data.methods || {};

        panel.querySelector('#node7-checkout-summary').textContent =
            `${changed} clothing change${changed === 1 ? '' : 's'} · $${total.toFixed(2)}`;

        paymentButtons.forEach((button) => {
            const configuredLabel = methods[button.dataset.paymentMethod];
            const label = configuredLabel || (button.dataset.paymentMethod === 'cash' ? 'Cash' : 'Bank');
            button.textContent = `Pay ${label}`;
            button.disabled = false;
        });

        panel.querySelector('#node7-checkout-cancel').disabled = false;
        statusNode.textContent = 'Select Cash or Bank to confirm.';
        panel.classList.add('is-visible');
        panel.setAttribute('aria-hidden', 'false');
        open = true;
    };

    const hide = () => {
        if (!panel) return;
        panel.classList.remove('is-visible');
        panel.setAttribute('aria-hidden', 'true');
        statusNode.textContent = '';
        paymentButtons.forEach((button) => { button.disabled = false; });
        open = false;
    };

    window.addEventListener('message', (event) => {
        const data = event.data || {};

        if (data.type === 'paymentMenu') {
            show(data);
            return;
        }

        if (data.type === 'paymentClose') {
            hide();
            return;
        }

        if (data.type === 'paymentResult') {
            ensurePanel();

            if (data.success) {
                statusNode.textContent = data.message || 'Purchase complete.';
                setTimeout(hide, 300);
            } else {
                statusNode.textContent = data.message || 'Payment failed.';
                paymentButtons.forEach((button) => { button.disabled = false; });
                panel.querySelector('#node7-checkout-cancel').disabled = false;
            }
        }
    });

    window.addEventListener('keydown', (event) => {
        if (!open) return;
        event.stopImmediatePropagation();

        if (event.key !== 'Escape') return;
        event.preventDefault();
        post('cancelPayment').then((result) => {
            if (result.ok) hide();
        });
    }, true);

    window.addEventListener('keyup', (event) => {
        if (!open) return;
        event.preventDefault();
        event.stopImmediatePropagation();
    }, true);

    installUiFixes();
})();
