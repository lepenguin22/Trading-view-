import React from 'react';
import { act, render, screen, waitFor } from '@testing-library/react-native';

import App from '../../App';
import chart1d from './fixtures/chart-1d.json';

/**
 * A smoke test over the real component tree: provider hydration, the polling
 * effect, navigation and the watchlist rows all run for real, with only the
 * network faked. It catches the class of crash that a type check cannot.
 */

const originalFetch = globalThis.fetch;

function mockFetchOk(payload: unknown) {
  globalThis.fetch = jest.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => payload,
  }) as unknown as typeof fetch;
}

beforeEach(() => {
  jest.useFakeTimers();
});

afterEach(() => {
  jest.runOnlyPendingTimers();
  jest.useRealTimers();
  globalThis.fetch = originalFetch;
  jest.restoreAllMocks();
});

describe('App', () => {
  it('renders the default watchlist with live prices', async () => {
    mockFetchOk(chart1d);

    render(<App />);

    // Every default symbol resolves to the same AAPL fixture, so the row for
    // the first default symbol is enough to prove the pipeline ran end to end.
    await waitFor(() => {
      expect(screen.getByText('Apple Inc.')).toBeTruthy();
    });

    expect(screen.getAllByText(/196\.50/).length).toBeGreaterThan(0);
    expect(screen.getAllByText('+1.29%').length).toBeGreaterThan(0);
  });

  it('shows the per-symbol error message when the feed fails', async () => {
    globalThis.fetch = jest.fn().mockRejectedValue(new Error('offline')) as unknown as typeof fetch;

    render(<App />);

    await waitFor(() => {
      expect(
        screen.getAllByText('Could not reach Yahoo Finance. Check your connection.').length,
      ).toBeGreaterThan(0);
    });
  });

  it('re-polls the feed on the refresh interval', async () => {
    mockFetchOk(chart1d);

    render(<App />);
    await waitFor(() => expect(screen.getByText('Apple Inc.')).toBeTruthy());

    const callsAfterFirstLoad = (globalThis.fetch as jest.Mock).mock.calls.length;
    expect(callsAfterFirstLoad).toBeGreaterThan(0);

    await act(async () => {
      jest.advanceTimersByTime(60_000);
    });

    await waitFor(() => {
      expect((globalThis.fetch as jest.Mock).mock.calls.length).toBeGreaterThan(callsAfterFirstLoad);
    });
  });
});
