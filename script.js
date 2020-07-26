window.onload = function() {
    // set the onclick event for every deleteLink
    Array.prototype.forEach.call(document.getElementsByClassName("deleteOrderLink"), deleteOrderLink => {
        deleteOrderLink.onclick = (eventArgs) => {
            deleteOrder(eventArgs.target.attributes["orderGuid"].value)
                .then(() => window.location.reload());
            // refresh the page
            //,,,,window.location.reload();
        }
    });

    // set the onclick event for the reloadOrdersLink
    document.getElementById("reloadOrdersLink").onclick = () => {
        reloadOrders()
            .then(window.location.reload);
        // refresh the page
        //,,,, window.location.reload();
    }
}

function deleteOrder(orderGuid) {
    return fetch(`/${orderGuid}`,
    {
        method: 'DELETE',
        body: `adminGuid=${adminGuid}`
    });
}

function reloadOrders() {
    // reload the orders from the XML file
    return fetch(`/${adminGuid}/reloadOrders`);
}