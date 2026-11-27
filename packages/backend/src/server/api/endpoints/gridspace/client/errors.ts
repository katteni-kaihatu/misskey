/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

import { ApiError } from '@/server/api/error.js';
import { GridspaceClientError } from '@/core/gridspace/client-read-protocol.js';
import { GridspaceLinkError } from '@/core/gridspace/GridspaceLinkService.js';

export const clientErrors = {
	appTokenRequired: { message: 'An application access token is required.', code: 'GRIDSPACE_CLIENT_APP_TOKEN_REQUIRED', id: '41573462-e374-4b2c-a604-44978059008e', httpStatusCode: 403 },
	permissionDenied: { message: 'The application does not have the required permission.', code: 'GRIDSPACE_CLIENT_PERMISSION_DENIED', id: 'e4d04e4e-52e8-44e0-8f73-e681d6317729', httpStatusCode: 403 },
	authorizationRevoked: { message: 'The application authorization changed or was revoked.', code: 'GRIDSPACE_CLIENT_AUTHORIZATION_REVOKED', id: '546abfdc-0c0a-4b9b-a285-8e138eac2891', httpStatusCode: 403 },
	invalidCursor: { message: 'The cursor is invalid or expired. Start a new read.', code: 'GRIDSPACE_CLIENT_INVALID_CURSOR', id: 'd07306a7-79eb-4b45-9c82-a897a510bca8', httpStatusCode: 400 },
	unavailable: { message: 'The requested reader is unavailable.', code: 'GRIDSPACE_CLIENT_UNAVAILABLE', id: '3feff018-13a7-4ca5-8d2b-4f6a765edb56', httpStatusCode: 503 },
} as const;

export function clientApiError(error: unknown): never {
	if (error instanceof GridspaceClientError) {
		switch (error.code) {
			case 'APP_TOKEN_REQUIRED': throw new ApiError(clientErrors.appTokenRequired);
			case 'PERMISSION_DENIED': throw new ApiError(clientErrors.permissionDenied);
			case 'AUTHORIZATION_REVOKED': throw new ApiError(clientErrors.authorizationRevoked);
			case 'INVALID_CURSOR': throw new ApiError(clientErrors.invalidCursor);
			case 'UNAVAILABLE': throw new ApiError(clientErrors.unavailable);
		}
	}
	if (error instanceof GridspaceLinkError) {
		if (error.code === 'INVALID_CURSOR') throw new ApiError(clientErrors.invalidCursor);
		if (['LINK_REVOKED', 'AUTHORIZATION_REVOKED'].includes(error.code)) throw new ApiError(clientErrors.authorizationRevoked);
		if (['UNAVAILABLE', 'PEER_UNAVAILABLE'].includes(error.code)) throw new ApiError(clientErrors.unavailable);
	}
	throw error;
}
