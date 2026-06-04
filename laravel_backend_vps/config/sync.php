<?php

$agentPolicyTicketSecret = trim((string) env('AGENT_POLICY_TICKET_SECRET', ''));
if ($agentPolicyTicketSecret === '') {
    $agentPolicyTicketSecret = trim((string) env('TODO_BACKEND_API_KEY', ''));
}
if ($agentPolicyTicketSecret === '') {
    $agentPolicyTicketSecret = trim((string) env('SYNC_API_KEY', ''));
}
if ($agentPolicyTicketSecret === '') {
    $agentPolicyTicketSecret = trim((string) env('APP_KEY', ''));
}
if ($agentPolicyTicketSecret === '') {
    $agentPolicyTicketSecret = 'dev-agent-policy-ticket-secret';
}

return [
    'api_key' => env('TODO_BACKEND_API_KEY', env('SYNC_API_KEY', '')),
    'locked_actor_profile' => env('SYNC_LOCKED_ACTOR_PROFILE', ''),
    'superadmin_phone' => env('SUPERADMIN_PHONE', '79679812438'),
    'agent_policy_ticket_secret' => $agentPolicyTicketSecret,
];
