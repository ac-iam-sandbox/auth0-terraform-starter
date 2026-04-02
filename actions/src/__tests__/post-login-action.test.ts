import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Event, PostLoginAPI } from '@auth0/actions/post-login/v3';
import { onExecutePostLogin } from '../post-login-action';

describe('Post Login Action - Enforce Verified Email', () => {
  let mockApi: Pick<PostLoginAPI, 'access'>;
  let mockEvent: Partial<Event>;

  beforeEach(() => {
    mockApi = {
      access: {
        deny: vi.fn(),
      },
    };

    mockEvent = {
      user: {
        email: 'test@example.com',
        email_verified: true,
      } as unknown as Event['user'],
    };
  });

  it('should allow login when email is verified', async () => {
    await onExecutePostLogin(mockEvent as Event, mockApi as PostLoginAPI);
    expect(mockApi.access.deny).not.toHaveBeenCalled();
  });

  it('should deny login when email is not verified', async () => {
    mockEvent.user = {
      email: 'test@example.com',
      email_verified: false,
    } as unknown as Event['user'];

    await onExecutePostLogin(mockEvent as Event, mockApi as PostLoginAPI);

    expect(mockApi.access.deny).toHaveBeenCalledWith(
      'Please verify your email address to continue.'
    );
  });

  it('should deny login when email_verified is undefined', async () => {
    mockEvent.user = {
      email: 'test@example.com',
    } as unknown as Event['user'];

    await onExecutePostLogin(mockEvent as Event, mockApi as PostLoginAPI);

    expect(mockApi.access.deny).toHaveBeenCalledWith(
      'Please verify your email address to continue.'
    );
  });

  it('should deny login when user is missing', async () => {
    mockEvent.user = undefined;

    await onExecutePostLogin(mockEvent as Event, mockApi as PostLoginAPI);

    expect(mockApi.access.deny).toHaveBeenCalledWith(
      'Please verify your email address to continue.'
    );
  });
});