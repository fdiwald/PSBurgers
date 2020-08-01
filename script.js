window.onload = function() {
    // set the onclick event for every deleteLink
    Array.prototype.forEach.call(document.getElementsByClassName("deleteOrderLink"), deleteOrderLink => {
        deleteOrderLink.onclick = (eventArgs) => {
            deleteOrder(eventArgs.target.attributes["orderGuid"].value)
                .then(() => window.location.reload());
        }
    });
}

function deleteOrder(orderGuid) {
    return fetch(`/${orderGuid}`,
    {
        method: 'DELETE',
        body: `adminGuid=${adminGuid}`
    });
}